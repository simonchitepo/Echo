import 'dart:async';

import '../lan/echo_nsd.dart';
import '../lan/lan_beacon.dart';

class DiscoveredBubble {
  final String bubbleId;
  final String bubbleName;
  final int peopleCountEstimate;
  final DateTime lastSeen;
  final String? host;
  final int? port;

  DiscoveredBubble({
    required this.bubbleId,
    required this.bubbleName,
    required this.peopleCountEstimate,
    required this.lastSeen,
    required this.host,
    required this.port,
  });
}

class BubbleDiscoveryService {
  BubbleDiscoveryService({
    required this.serviceType,
  });

  final String serviceType;

  final EchoNsd _nsd = EchoNsd();

  // ✅ UDP beacon fallback (optional second signal path)
  final LanBeacon _beacon = LanBeacon();

  final _ctrl = StreamController<List<DiscoveredBubble>>.broadcast();
  Stream<List<DiscoveredBubble>> get bubblesStream => _ctrl.stream;

  final Map<String, _BubbleState> _bubbles = {}; // bubbleId -> state
  Timer? _prune;

  StreamSubscription? _subNsd;
  StreamSubscription? _subBeacon;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    // NSD discovery (EchoNsd UDP beacons / mDNS replacement)
    await _nsd.startDiscovery(serviceType: serviceType);
    _subNsd ??= _nsd.foundStream.listen(_onFoundNsd);

    // ✅ Optional beacon listener (second channel)
    await _beacon.startListener();
    _subBeacon ??= _beacon.incoming.listen(_onFoundBeacon);

    _prune ??= Timer.periodic(const Duration(seconds: 5), (_) => _pruneOld());
  }

  void _onFoundNsd(EchoNsdServiceInfo svc) {
    final txt = svc.txt;

    final bubbleId = (txt['bubbleId'] ?? '').trim();
    if (bubbleId.isEmpty) return;

    final peerId = (txt['peerId'] ?? '').trim();
    final displayName = (txt['displayName'] ?? '').trim();

    final host = svc.host;
    final port = svc.port;

    final now = DateTime.now();

    final bs = _bubbles.putIfAbsent(bubbleId, () => _BubbleState(bubbleId));
    bs.lastSeen = now;

    if (peerId.isNotEmpty) {
      bs.peers[peerId] = now;
    }

    // Deterministic "best host": lowest peerId wins.
    if (host != null && port != null && peerId.isNotEmpty) {
      if (bs.bestPeerId == null || peerId.compareTo(bs.bestPeerId!) < 0) {
        bs.bestPeerId = peerId;
        bs.bestHost = host;
        bs.bestPort = port;
        bs.bestName = displayName.isEmpty ? bs.bestName : displayName;
      }
    } else {
      // Fallback: accept first host/port we see if we don't have one yet
      bs.bestHost ??= host;
      bs.bestPort ??= port;
      if (bs.bestName == null || bs.bestName!.isEmpty) {
        bs.bestName = displayName;
      }
    }

    _emit();
  }

  void _onFoundBeacon(Map<String, dynamic> pkt) {
    // Expect: type=echo_beacon, bubbleId, peerId, wsPort, host
    if (pkt['type'] != 'echo_beacon') return;

    final bubbleId = (pkt['bubbleId'] ?? '').toString().trim();
    if (bubbleId.isEmpty) return;

    final peerId = (pkt['peerId'] ?? '').toString().trim();
    final wsPortRaw = pkt['wsPort'];
    final host = (pkt['host'] ?? '').toString().trim();

    final wsPort = wsPortRaw is int ? wsPortRaw : int.tryParse(wsPortRaw.toString());
    if (host.isEmpty || wsPort == null) return;

    final now = DateTime.now();

    final bs = _bubbles.putIfAbsent(bubbleId, () => _BubbleState(bubbleId));
    bs.lastSeen = now;

    if (peerId.isNotEmpty) {
      bs.peers[peerId] = now;
    }

    // Prefer deterministic lowest peerId; if none, accept first.
    if (peerId.isNotEmpty) {
      if (bs.bestPeerId == null || peerId.compareTo(bs.bestPeerId!) < 0) {
        bs.bestPeerId = peerId;
        bs.bestHost = host;
        bs.bestPort = wsPort;
      }
    } else if (bs.bestHost == null) {
      bs.bestHost = host;
      bs.bestPort = wsPort;
    }

    _emit();
  }

  void _pruneOld() {
    final now = DateTime.now();

    // Remove bubbles not seen for 15 seconds
    _bubbles.removeWhere((_, bs) => now.difference(bs.lastSeen) > const Duration(seconds: 15));

    // Remove peers not seen for 15 seconds
    for (final bs in _bubbles.values) {
      bs.peers.removeWhere((_, t) => now.difference(t) > const Duration(seconds: 15));
    }

    _emit();
  }

  void _emit() {
    final list = _bubbles.values
        .map((bs) {
      return DiscoveredBubble(
        bubbleId: bs.bubbleId,
        bubbleName: _friendlyBubbleName(bs.bubbleId),
        peopleCountEstimate: bs.peers.length,
        lastSeen: bs.lastSeen,
        host: bs.bestHost,
        port: bs.bestPort,
      );
    })
        .toList()
      ..sort((a, b) => b.peopleCountEstimate.compareTo(a.peopleCountEstimate));

    if (!_ctrl.isClosed) _ctrl.add(list);
  }

  String _friendlyBubbleName(String bubbleId) {
    if (bubbleId.startsWith('here|')) return 'Here & Now';
    return 'Bubble ${bubbleId.length >= 6 ? bubbleId.substring(0, 6) : bubbleId}';
  }

  Future<void> stop() async {
    _started = false;

    await _subNsd?.cancel();
    _subNsd = null;

    await _subBeacon?.cancel();
    _subBeacon = null;

    _prune?.cancel();
    _prune = null;

    _bubbles.clear();

    // ✅ IMPORTANT:
    // Do NOT call _nsd.dispose() here. dispose() closes its internal stream controller.
    // If you stop/start discovery again in the same app run, discovery can break silently.
    await _nsd.stopDiscovery();

    await _beacon.dispose();
  }

  Future<void> dispose() async {
    // Full permanent cleanup
    await stop();
    await _nsd.dispose();
    await _ctrl.close();
  }
}

class _BubbleState {
  final String bubbleId;
  _BubbleState(this.bubbleId);

  DateTime lastSeen = DateTime.now();
  final Map<String, DateTime> peers = {};

  String? bestPeerId;
  String? bestHost;
  int? bestPort;
  String? bestName;
}