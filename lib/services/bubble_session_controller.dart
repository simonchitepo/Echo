import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/bubble_event.dart';
import '../models/bubble_shout.dart';
import '../models/canvas_stroke.dart';
import '../models/clipboard_item.dart';
import '../models/pulse_poll.dart';
import '../models/status_badge.dart';
import '../services/echo_comms.dart';

/// In-memory state for a single joined bubble.
///
/// ⚠️ IMPORTANT CHANGE:
/// - We no longer assume "leaving the page" means "wipe state".
/// - State is only wiped when you explicitly call [shutdownBubble] (your "turn off" action).
class BubbleSessionController {
  final List<EchoComms> comms;
  final String bubbleId;
  final String myDisplayName;

  /// A stable id for event payloads (distinct from transport endpoint ids).
  ///
  /// Reason: LAN and Nearby use different peer ids. For event dedupe and "my vote" tracking,
  /// we use a logical per-device id.
  final String myEventPeerId;

  /// Indicates the user explicitly turned the bubble off.
  bool _shutdown = false;
  bool get isShutdown => _shutdown;

  final ValueNotifier<BubbleShout?> shout = ValueNotifier<BubbleShout?>(null);
  final ValueNotifier<Color> heatColor = ValueNotifier<Color>(Colors.transparent);
  final ValueNotifier<double> heatIntensity = ValueNotifier<double>(0);
  final ValueNotifier<List<PulsePoll>> polls = ValueNotifier<List<PulsePoll>>(<PulsePoll>[]);
  final ValueNotifier<List<CanvasStroke>> strokes = ValueNotifier<List<CanvasStroke>>(<CanvasStroke>[]);
  final ValueNotifier<Map<String, StatusBadge>> badgesByPeer =
  ValueNotifier<Map<String, StatusBadge>>(<String, StatusBadge>{});
  final ValueNotifier<List<ClipboardItem>> clipboardInbox =
  ValueNotifier<List<ClipboardItem>>(<ClipboardItem>[]);

  final _rng = Random();
  final _subs = <StreamSubscription>[];
  Timer? _tick;

  // Heat pulses: list of (ts, color)
  final List<_Pulse> _pulses = <_Pulse>[];

  BubbleSessionController({
    required this.comms,
    required this.bubbleId,
    required this.myDisplayName,
    String? myEventPeerId,
  }) : myEventPeerId = myEventPeerId ?? const Uuid().v4() {
    for (final c in comms) {
      _subs.add(c.eventsStream.listen(_onEvent));
    }
    _tick = Timer.periodic(const Duration(milliseconds: 350), (_) => _maintenanceTick());
  }

  /// Call this when the user explicitly turns the bubble OFF.
  ///
  /// - Stops comms
  /// - Wipes all state
  Future<void> shutdownBubble() async {
    if (_shutdown) return;
    _shutdown = true;

    // stop all transports
    for (final c in comms) {
      try {
        if (c.isRunning) {
          await c.stop();
        }
      } catch (_) {}
    }

    // wipe state
    reset();
  }

  /// Dispose listeners/timers. Does NOT wipe state automatically.
  /// Wiping is now controlled via [shutdownBubble] or manual [reset].
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();

    _tick?.cancel();
    _tick = null;

    // Notifiers
    shout.dispose();
    heatColor.dispose();
    heatIntensity.dispose();
    polls.dispose();
    strokes.dispose();
    badgesByPeer.dispose();
    clipboardInbox.dispose();
  }

  /// Manual wipe (use if you intentionally want to clear memory while keeping comms running).
  void reset() {
    shout.value = null;
    heatColor.value = Colors.transparent;
    heatIntensity.value = 0;
    polls.value = <PulsePoll>[];
    strokes.value = <CanvasStroke>[];
    badgesByPeer.value = <String, StatusBadge>{};
    clipboardInbox.value = <ClipboardItem>[];
    _pulses.clear();
  }

  // ---------------------------------------------------------------------------
  // Outgoing helpers
  // ---------------------------------------------------------------------------

  Future<void> setShout(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    final evt = _evt(
      kind: 'shout/set',
      ttlSeconds: 60,
      data: {'text': t},
    );
    await _broadcast(evt);
  }

  Future<void> sendPulse(Color color) async {
    final evt = _evt(
      kind: 'pulse',
      ttlSeconds: 10,
      data: {'color': color.value},
    );
    await _broadcast(evt);
  }

  Future<void> createPoll({required String question, required List<String> options}) async {
    final q = question.trim();
    final opts = options.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (q.isEmpty || opts.length < 2) return;
    if (opts.length > 6) opts.removeRange(6, opts.length);

    final pollId = const Uuid().v4();
    final evt = _evt(
      kind: 'poll/create',
      ttlSeconds: 600,
      data: {
        'pollId': pollId,
        'question': q,
        'options': opts,
      },
    );
    await _broadcast(evt);
  }

  Future<void> votePoll({required String pollId, required int optionIdx}) async {
    final evt = _evt(
      kind: 'poll/vote',
      ttlSeconds: 600,
      data: {
        'pollId': pollId,
        'optionIdx': optionIdx,
      },
    );
    await _broadcast(evt);
  }

  Future<void> setBadge(String label) async {
    final l = label.trim();
    if (l.isEmpty) return;
    final evt = _evt(
      kind: 'badge/set',
      ttlSeconds: 3600,
      data: {'label': l},
    );
    await _broadcast(evt);
  }

  Future<void> sendStroke(CanvasStroke stroke) async {
    final evt = _evt(
      kind: 'canvas/stroke',
      ttlSeconds: 7200,
      data: {'stroke': stroke.toJson()},
    );
    await _broadcast(evt);
  }

  Future<void> clearCanvas() async {
    final evt = _evt(kind: 'canvas/clear', ttlSeconds: 60, data: {});
    await _broadcast(evt);
  }

  Future<void> pushClipboard({required String toPeerId, required String text}) async {
    final t = text.trim();
    if (t.isEmpty) return;
    final evt = _evt(
      kind: 'clipboard/push',
      ttlSeconds: 300,
      data: {'text': t},
    );
    await _sendDirect(evt, toPeerId);
  }

  // ---------------------------------------------------------------------------
  // Incoming event router
  // ---------------------------------------------------------------------------

  void _onEvent(BubbleEvent e) {
    if (e.bubbleId != bubbleId) return;

    switch (e.kind) {
      case 'shout/set':
        _applyShout(e);
        break;
      case 'pulse':
        _applyPulse(e);
        break;
      case 'poll/create':
        _applyPollCreate(e);
        break;
      case 'poll/vote':
        _applyPollVote(e);
        break;
      case 'badge/set':
        _applyBadge(e);
        break;
      case 'canvas/stroke':
        _applyStroke(e);
        break;
      case 'canvas/clear':
        strokes.value = <CanvasStroke>[];
        break;
      case 'clipboard/push':
        _applyClipboard(e);
        break;
      default:
      // Ignore unknown kinds to preserve forwards compatibility.
        break;
    }
  }

  void _applyShout(BubbleEvent e) {
    final text = (e.data['text'] as String?)?.trim();
    if (text == null || text.isEmpty) return;
    final createdAt = e.ts;
    final expiresAt = createdAt.add(Duration(seconds: e.ttlSeconds ?? 60));
    shout.value = BubbleShout(
      text: text,
      fromPeerId: e.fromPeerId,
      fromName: e.fromName,
      createdAt: createdAt,
      expiresAt: expiresAt,
    );
  }

  void _applyPulse(BubbleEvent e) {
    final c = e.data['color'];
    if (c is! int) return;
    _pulses.add(_Pulse(at: e.ts, colorValue: c));
    _recomputeHeat();
  }

  void _applyPollCreate(BubbleEvent e) {
    final pollId = (e.data['pollId'] as String?)?.trim();
    final q = (e.data['question'] as String?)?.trim();
    final opts = e.data['options'];
    if (pollId == null || pollId.isEmpty) return;
    if (q == null || q.isEmpty) return;
    if (opts is! List) return;

    final options = opts.map((x) => x.toString()).toList();
    if (options.length < 2) return;

    final createdAt = e.ts;
    final expiresAt = createdAt.add(const Duration(minutes: 10));
    final list = List<PulsePoll>.from(polls.value);

    // Replace if same pollId (idempotent)
    list.removeWhere((p) => p.pollId == pollId);
    list.add(
      PulsePoll(
        pollId: pollId,
        question: q,
        options: options,
        createdAt: createdAt,
        expiresAt: expiresAt,
        createdByPeerId: e.fromPeerId,
        createdByName: e.fromName,
      ),
    );

    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    polls.value = list;
  }

  void _applyPollVote(BubbleEvent e) {
    final pollId = (e.data['pollId'] as String?)?.trim();
    final optionIdx = e.data['optionIdx'];
    if (pollId == null || pollId.isEmpty) return;
    if (optionIdx is! int) return;

    final list = List<PulsePoll>.from(polls.value);
    final i = list.indexWhere((p) => p.pollId == pollId);
    if (i < 0) return;

    final p = list[i];
    if (p.isExpired) return;
    if (optionIdx < 0 || optionIdx >= p.options.length) return;

    // Dedupe by peer: adjust counts if vote changed
    final prev = p.myVotesByPeer[e.fromPeerId];
    if (prev == optionIdx) return;

    if (prev != null && prev >= 0 && prev < p.counts.length) {
      p.counts[prev] = max(0, p.counts[prev] - 1);
    }

    p.myVotesByPeer[e.fromPeerId] = optionIdx;
    p.counts[optionIdx] = p.counts[optionIdx] + 1;

    polls.value = list;
  }

  void _applyBadge(BubbleEvent e) {
    final label = (e.data['label'] as String?)?.trim();
    if (label == null || label.isEmpty) return;

    final setAt = e.ts;
    final expiresAt = setAt.add(Duration(seconds: e.ttlSeconds ?? 3600));

    final map = Map<String, StatusBadge>.from(badgesByPeer.value);
    map[e.fromPeerId] = StatusBadge(label: label, setAt: setAt, expiresAt: expiresAt);
    badgesByPeer.value = map;
  }

  void _applyStroke(BubbleEvent e) {
    final raw = e.data['stroke'];
    if (raw is! Map) return;

    final stroke = CanvasStroke.tryFromJson(Map<String, dynamic>.from(raw));
    if (stroke == null) return;

    final list = List<CanvasStroke>.from(strokes.value);

    // Dedupe by strokeId
    if (list.any((s) => s.strokeId == stroke.strokeId)) return;

    list.add(stroke);
    strokes.value = list;
  }

  void _applyClipboard(BubbleEvent e) {
    final text = (e.data['text'] as String?)?.trim();
    if (text == null || text.isEmpty) return;

    final createdAt = e.ts;
    final expiresAt = createdAt.add(const Duration(minutes: 5));

    final item = ClipboardItem(
      itemId: e.eventId,
      text: text,
      fromPeerId: e.fromPeerId,
      fromName: e.fromName,
      createdAt: createdAt,
      expiresAt: expiresAt,
    );

    final list = List<ClipboardItem>.from(clipboardInbox.value);
    list.insert(0, item);
    clipboardInbox.value = list;
  }

  // ---------------------------------------------------------------------------
  // Maintenance tick (expire TTL features)
  // ---------------------------------------------------------------------------

  void _maintenanceTick() {
    // Shout expiry
    final s = shout.value;
    if (s != null && s.isExpired) shout.value = null;

    // Poll expiry
    final plist = polls.value;
    final filtered = plist.where((p) => !p.isExpired).toList();
    if (filtered.length != plist.length) polls.value = filtered;

    // Clipboard expiry
    final cb = clipboardInbox.value;
    final cbFiltered = cb.where((c) => !c.isExpired).toList();
    if (cbFiltered.length != cb.length) clipboardInbox.value = cbFiltered;

    // Badge expiry
    final bmap = badgesByPeer.value;
    final bFiltered = <String, StatusBadge>{
      for (final e in bmap.entries)
        if (!e.value.isExpired) e.key: e.value,
    };
    if (bFiltered.length != bmap.length) badgesByPeer.value = bFiltered;

    // Heat decay
    _recomputeHeat();
  }

  void _recomputeHeat() {
    final now = DateTime.now();
    _pulses.removeWhere((p) => now.difference(p.at) > const Duration(seconds: 10));

    if (_pulses.isEmpty) {
      heatIntensity.value = 0;
      heatColor.value = Colors.transparent;
      return;
    }

    // Weighted: recent pulses count more.
    double r = 0, g = 0, b = 0, wsum = 0;
    for (final p in _pulses) {
      final age = now.difference(p.at).inMilliseconds.clamp(0, 10000) / 10000.0;
      final w = 1.0 - age; // linear decay
      final c = Color(p.colorValue);
      r += c.red * w;
      g += c.green * w;
      b += c.blue * w;
      wsum += w;
    }

    final avg = Color.fromARGB(
      255,
      (r / wsum).round().clamp(0, 255),
      (g / wsum).round().clamp(0, 255),
      (b / wsum).round().clamp(0, 255),
    );
    heatColor.value = avg;

    // Intensity -> how many pulses recently (cap around 18)
    final intensity = (_pulses.length / 18.0).clamp(0.0, 1.0);
    heatIntensity.value = intensity;
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  BubbleEvent _evt({
    required String kind,
    required Map<String, dynamic> data,
    int? ttlSeconds,
  }) {
    return BubbleEvent(
      eventId: const Uuid().v4(),
      bubbleId: bubbleId,
      kind: kind,
      data: data,
      fromPeerId: myEventPeerId,
      fromName: myDisplayName,
      toPeerId: '*',
      ts: DateTime.now(),
      ttlSeconds: ttlSeconds,
    );
  }

  Future<void> _broadcast(BubbleEvent e) async {
    for (final c in comms) {
      if (c.isRunning) {
        await c.sendEvent(e, toPeerId: '*');
      }
    }
  }

  Future<void> _sendDirect(BubbleEvent e, String toPeerId) async {
    for (final c in comms) {
      if (c.isRunning) {
        await c.sendEvent(e, toPeerId: toPeerId);
      }
    }
  }

  Color randomVibeColor() {
    const palette = <Color>[
      Colors.pink,
      Colors.orange,
      Colors.amber,
      Colors.green,
      Colors.teal,
      Colors.blue,
      Colors.purple,
    ];
    return palette[_rng.nextInt(palette.length)];
  }
}

class _Pulse {
  final DateTime at;
  final int colorValue;
  _Pulse({required this.at, required this.colorValue});
}