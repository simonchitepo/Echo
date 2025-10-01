import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/canvas_stroke.dart';
import '../models/pulse_poll.dart';
import '../services/bubble_session_controller.dart';

class BubblePage extends StatefulWidget {
  final BubbleSessionController controller;
  const BubblePage({super.key, required this.controller});

  @override
  State<BubblePage> createState() => _BubblePageState();
}

class _BubblePageState extends State<BubblePage> {
  static const Color _brandGreen = Color(0xFF0F9D58);
  static const Color _liveRed = Color(0xFFE53935);
  static const Color _softField = Color(0xFFF7F8F7);
  final _shoutCtrl = TextEditingController();
  final _pollQuestionCtrl = TextEditingController();
  final List<TextEditingController> _pollOptCtrls = <TextEditingController>[];
  final _badgeCtrl = TextEditingController();
  final _clipTextCtrl = TextEditingController();
  final _clipToPeerCtrl = TextEditingController(text: '*');

  Color _penColor = _brandGreen;
  double _penWidth = 3.5;
  List<Offset> _currentPoints = <Offset>[];

  bool _canvasFullscreen = false;
  bool _eraser = false;

  int _lastInboxCount = 0;
  bool _inboxPulse = false;
  Timer? _inboxPulseTimer;

  @override
  void initState() {
    super.initState();


    _pollOptCtrls.add(TextEditingController());
    _pollOptCtrls.add(TextEditingController());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = widget.controller;
      _lastInboxCount = c.clipboardInbox.value.length;
      c.clipboardInbox.addListener(_onInboxChanged);
    });
  }

  void _onInboxChanged() {
    final c = widget.controller;
    final nowCount = c.clipboardInbox.value.length;
    if (nowCount > _lastInboxCount) {
      final newItems = nowCount - _lastInboxCount;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📎 Beam received ($newItems)'),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      setState(() => _inboxPulse = true);
      _inboxPulseTimer?.cancel();
      _inboxPulseTimer = Timer(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        setState(() => _inboxPulse = false);
      });
    }
    _lastInboxCount = nowCount;
  }

  @override
  void dispose() {
    widget.controller.clipboardInbox.removeListener(_onInboxChanged);
    _inboxPulseTimer?.cancel();

    _shoutCtrl.dispose();
    _pollQuestionCtrl.dispose();
    for (final c in _pollOptCtrls) {
      c.dispose();
    }
    _badgeCtrl.dispose();
    _clipTextCtrl.dispose();
    _clipToPeerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bubble'),
        actions: [
          IconButton(
            tooltip: 'Send vibe pulse',
            onPressed: () => c.sendPulse(c.randomVibeColor()),
            icon: const Icon(Icons.waves),
          ),
          IconButton(
            tooltip: 'Connection info',
            onPressed: () => _showConnectionInfo(c),
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
      body: Stack(
        children: [
          ValueListenableBuilder<Color>(
            valueListenable: c.heatColor,
            builder: (_, col, __) {
              return ValueListenableBuilder<double>(
                valueListenable: c.heatIntensity,
                builder: (_, inten, __) {
                  if (inten <= 0) return const SizedBox.shrink();
                  return IgnorePointer(
                    child: Opacity(
                      opacity: (0.12 + 0.55 * inten).clamp(0.0, 0.85),
                      child: Container(color: col),
                    ),
                  );
                },
              );
            },
          ),

          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _statusPillRow(),
              const SizedBox(height: 14),
              _buzzCard(c),
              const SizedBox(height: 14),

              LayoutBuilder(
                builder: (ctx, constraints) {
                  final wide = constraints.maxWidth >= 760;

                  final cards = <Widget>[
                    _bentoCard(
                      title: 'Pulse Check',
                      subtitle: '10-minute polls',
                      icon: Icons.poll_outlined,
                      pulse: false,
                      gridMode: wide,
                      child: wide
                          ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _pollComposer(c),
                          const SizedBox(height: 10),
                          Expanded(child: _pollList(c, scrollable: true)),
                        ],
                      )
                          : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _pollComposer(c),
                          const SizedBox(height: 10),
                          _pollList(c, scrollable: false),
                        ],
                      ),
                    ),
                    _bentoCard(
                      title: 'Bubble Canvas',
                      subtitle: 'Session graffiti wall',
                      icon: Icons.draw_outlined,
                      pulse: false,
                      gridMode: wide,
                      child: _canvasCard(c),
                    ),
                    _bentoCard(
                      title: 'Status Badge',
                      subtitle: '1-hour vibe label',
                      icon: Icons.verified_outlined,
                      pulse: false,
                      gridMode: wide,
                      child: _badgeCard(c),
                    ),
                    _bentoCard(
                      title: 'Shared Clipboard',
                      subtitle: 'Direct beam + inbox',
                      icon: Icons.inbox_outlined,
                      pulse: _inboxPulse,
                      gridMode: wide,
                      child: _clipboardCard(c),
                    ),
                  ];

                  if (!wide) {
                    return Column(
                      children: [
                        for (int i = 0; i < cards.length; i++) ...[
                          cards[i],
                          if (i != cards.length - 1) const SizedBox(height: 12),
                        ],
                      ],
                    );
                  }

                  return GridView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.55,
                    ),
                    children: cards,
                  );
                },
              ),

              const SizedBox(height: 18),
              Text(
                'Everything here is local and ephemeral. When the last person leaves, it naturally disappears.',
                style: TextStyle(color: Colors.black.withOpacity(0.60), height: 1.25),
              ),
              const SizedBox(height: 30),
            ],
          ),

          if (_canvasFullscreen) _canvasFullscreenOverlay(c),
        ],
      ),
    );
  }

  Widget _statusPillRow() {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.80),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.black.withOpacity(0.06)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _brandGreen,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _brandGreen.withOpacity(0.30),
                        blurRadius: 14,
                        spreadRadius: 1,
                      )
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    '• Local Node Active',
                    style: TextStyle(fontWeight: FontWeight.w900),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.waves, size: 18, color: Colors.black.withOpacity(0.55)),
                const SizedBox(width: 6),
                Text(
                  'Tap waves',
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.55),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showConnectionInfo(BubbleSessionController c) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final id = c.myEventPeerId;
        return AlertDialog(
          title: const Text('Connection info'),
          content: SelectableText(
            'Local node id:\n$id\n\n'
                'Share this id only if you want someone to beam you a clipboard item directly.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
          ],
        );
      },
    );
  }

  Widget _buzzCard(BubbleSessionController c) {
    return ValueListenableBuilder(
      valueListenable: c.shout,
      builder: (_, shout, __) {
        final has = shout != null;
        final remain = has ? shout!.remaining.inSeconds.clamp(0, 60) : 0;
        final who = has ? (shout!.fromName ?? 'Someone').trim() : '';

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0.92),
                Colors.white.withOpacity(0.82),
              ],
            ),
            border: Border.all(color: Colors.black.withOpacity(0.06)),
            boxShadow: [
              BoxShadow(
                color: (has ? _liveRed : Colors.black).withOpacity(has ? 0.14 : 0.06),
                blurRadius: has ? 22 : 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: has ? _liveRed.withOpacity(0.10) : Colors.black.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.black.withOpacity(0.06)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          has ? Icons.campaign : Icons.campaign_outlined,
                          size: 16,
                          color: has ? _liveRed : Colors.black.withOpacity(0.65),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '60-Second Echo',
                          style: TextStyle(fontWeight: FontWeight.w900, color: Colors.black.withOpacity(0.80)),
                        ),
                        if (has) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _liveRed,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: _liveRed.withOpacity(0.35),
                                  blurRadius: 16,
                                  spreadRadius: 1,
                                )
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (has)
                    Text(
                      '${remain}s',
                      style: TextStyle(color: Colors.black.withOpacity(0.60), fontWeight: FontWeight.w900),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (!has)
                Text(
                  'No buzz right now. Drop one to the room.',
                  style: TextStyle(color: Colors.black.withOpacity(0.65), fontWeight: FontWeight.w700),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(shout!.text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    Text('$who · fading soon', style: TextStyle(color: Colors.black.withOpacity(0.55), fontWeight: FontWeight.w700)),
                  ],
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _shoutCtrl,
                      decoration: InputDecoration(
                        hintText: 'Ask the room… “Anyone got a charger?”',
                        filled: true,
                        fillColor: _softField,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _pillButton(
                    label: 'Echo',
                    icon: Icons.send_rounded,
                    onPressed: () async {
                      final text = _shoutCtrl.text.trim();
                      _shoutCtrl.clear();
                      await c.setShout(text);
                    },
                    primary: true,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _bentoCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
    required bool gridMode,
    bool pulse = false,
  }) {
    final shadow = BoxShadow(
      color: Colors.black.withOpacity(0.06),
      blurRadius: 18,
      offset: const Offset(0, 10),
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white.withOpacity(0.90),
        border: Border.all(color: Colors.black.withOpacity(0.07)),
        boxShadow: [
          shadow,
          if (pulse)
            BoxShadow(
              color: _brandGreen.withOpacity(0.16),
              blurRadius: 26,
              spreadRadius: 1,
              offset: const Offset(0, 12),
            ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black.withOpacity(0.06)),
                ),
                child: Icon(icon, color: Colors.black.withOpacity(0.70)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: Colors.black.withOpacity(0.55), fontWeight: FontWeight.w700, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (gridMode) Expanded(child: child) else child,
        ],
      ),
    );
  }

  Widget _pollComposer(BubbleSessionController c) {
    return Column(
      children: [
        TextField(
          controller: _pollQuestionCtrl,
          decoration: InputDecoration(
            hintText: 'Drop a 10-minute pulse check…',
            filled: true,
            fillColor: _softField,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 10),
        for (int i = 0; i < _pollOptCtrls.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              controller: _pollOptCtrls[i],
              decoration: InputDecoration(
                hintText: 'Option ${i + 1}',
                filled: true,
                fillColor: _softField,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ),
        Row(
          children: [
            Flexible(
              child: _pillButton(
                label: _pollOptCtrls.length >= 4 ? 'Max options' : 'Add option',
                icon: Icons.add,
                onPressed: _pollOptCtrls.length >= 4
                    ? null
                    : () => setState(() => _pollOptCtrls.add(TextEditingController())),
                primary: false,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: _pillButton(
                label: 'Drop poll',
                icon: Icons.rocket_launch_outlined,
                primary: true,
                onPressed: () async {
                  final q = _pollQuestionCtrl.text.trim();
                  final opts = _pollOptCtrls.map((e) => e.text.trim()).where((t) => t.isNotEmpty).toList();

                  if (q.isEmpty || opts.length < 2) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add a question + at least 2 options.')));
                    return;
                  }

                  await c.createPoll(question: q, options: opts);

                  _pollQuestionCtrl.clear();
                  for (final o in _pollOptCtrls) {
                    o.clear();
                  }

                  setState(() {
                    for (int i = 2; i < _pollOptCtrls.length; i++) {
                      _pollOptCtrls[i].dispose();
                    }
                    _pollOptCtrls
                      ..clear()
                      ..add(TextEditingController())
                      ..add(TextEditingController());
                  });
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _pollList(BubbleSessionController c, {required bool scrollable}) {
    return ValueListenableBuilder<List<PulsePoll>>(
      valueListenable: c.polls,
      builder: (_, list, __) {
        if (list.isEmpty) {
          return Text('No active polls.', style: TextStyle(color: Colors.black.withOpacity(0.55), fontWeight: FontWeight.w700));
        }
        if (scrollable) {
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) => _pollCard(c, list[i]),
          );
        }
        return Column(children: [for (final p in list) _pollCard(c, p)]);
      },
    );
  }

  Widget _pollCard(BubbleSessionController c, PulsePoll p) {
    final remain = max(0, p.remaining.inSeconds);
    final who = (p.createdByName ?? 'Someone').trim();
    final total = p.counts.fold<int>(0, (a, b) => a + b).clamp(0, 1 << 30);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: _softField,
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.question, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(
            '$who · ${remain ~/ 60}m ${remain % 60}s · $total vote(s)',
            style: TextStyle(color: Colors.black.withOpacity(0.55), fontWeight: FontWeight.w700, fontSize: 12),
          ),
          const SizedBox(height: 10),
          for (int i = 0; i < p.options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _pollOptionRow(
                label: p.options[i],
                count: p.counts[i],
                total: total,
                colorSeed: i,
                onVote: () => c.votePoll(pollId: p.pollId, optionIdx: i),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pollOptionRow({
    required String label,
    required int count,
    required int total,
    required int colorSeed,
    required VoidCallback onVote,
  }) {
    final pct = total == 0 ? 0.0 : (count / total).clamp(0.0, 1.0);
    final hue = (colorSeed * 62.0) % 360.0;
    final col = HSVColor.fromAHSV(1, hue, 0.55, 0.85).toColor();

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onVote,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.72),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black.withOpacity(0.06)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 18,
                      backgroundColor: Colors.black.withOpacity(0.05),
                      valueColor: AlwaysStoppedAnimation(col.withOpacity(0.85)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text('$count', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.black.withOpacity(0.70))),
          ],
        ),
      ),
    );
  }

  Widget _canvasCard(BubbleSessionController c) {
    const h = 260.0;

    return Column(
      children: [
        SizedBox(
          height: h,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.white.withOpacity(0.85), Colors.white.withOpacity(0.70)],
                      ),
                    ),
                    child: GestureDetector(
                      onPanStart: (d) => _currentPoints = [d.localPosition],
                      onPanUpdate: (d) => setState(() => _currentPoints.add(d.localPosition)),
                      onPanEnd: (_) async {
                        final pts = List<Offset>.from(_currentPoints);
                        _currentPoints = <Offset>[];
                        setState(() {});
                        if (pts.length < 2) return;

                        final color = _eraser ? Colors.transparent : _penColor;
                        final stroke = CanvasStroke(
                          strokeId: const Uuid().v4(),
                          fromPeerId: c.myEventPeerId,
                          colorValue: color.value,
                          width: _penWidth,
                          points: pts,
                        );
                        await c.sendStroke(stroke);
                      },
                      child: ValueListenableBuilder<List<CanvasStroke>>(
                        valueListenable: c.strokes,
                        builder: (_, strokes, __) {
                          return CustomPaint(
                            painter: _CanvasPainter(
                              strokes: strokes,
                              current: _currentPoints,
                              currentColor: _eraser ? Colors.transparent : _penColor,
                              currentWidth: _penWidth,
                              eraser: _eraser,
                            ),
                            size: Size.infinite,
                          );
                        },
                      ),
                    ),
                  ),
                ),

                Positioned(
                  right: 10,
                  top: 10,
                  child: _iconChip(
                    icon: Icons.open_in_full,
                    tooltip: 'Full screen',
                    onTap: () => setState(() => _canvasFullscreen = true),
                  ),
                ),

                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 10,
                  child: _toolBelt(c),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _colorDot(_penColor, onTap: () => setState(() => _penColor = c.randomVibeColor())),
            const SizedBox(width: 10),
            _brushDot(_penWidth, color: _eraser ? Colors.black.withOpacity(0.25) : _penColor),
            const SizedBox(width: 10),
            Expanded(
              child: Slider(
                value: _penWidth,
                min: 2,
                max: 12,
                onChanged: (v) => setState(() => _penWidth = v),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _toolBelt(BubbleSessionController c) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 320;

        return Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.82),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.black.withOpacity(0.07)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 16,
                offset: const Offset(0, 10),
              )
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.max,
            children: [
              _beltButton(
                icon: Icons.brush_outlined,
                label: 'Pen',
                active: !_eraser,
                compact: compact,
                onTap: () => setState(() => _eraser = false),
              ),
              SizedBox(width: compact ? 6 : 10),
              _beltButton(
                icon: Icons.auto_fix_high_outlined,
                label: 'Eraser',
                active: _eraser,
                compact: compact,
                onTap: () => setState(() => _eraser = true),
              ),
              SizedBox(width: compact ? 6 : 10),
              _beltButton(
                icon: Icons.delete_outline,
                label: 'Clear',
                danger: true,
                compact: compact,
                onTap: () => c.clearCanvas(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _beltButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
    bool danger = false,
    bool compact = false,
  }) {
    final col = danger ? _liveRed : (active ? _brandGreen : Colors.black.withOpacity(0.70));

    final padH = compact ? 10.0 : 12.0;
    final padV = compact ? 8.0 : 8.0;

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
        decoration: BoxDecoration(
          color: col.withOpacity(active ? 0.10 : 0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.black.withOpacity(0.06)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: col),
            if (!compact) ...[
              const SizedBox(width: 8),
              Text(label, style: TextStyle(fontWeight: FontWeight.w900, color: col)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _brushDot(double width, {required Color color}) {
    final size = (width * 1.7).clamp(6.0, 22.0);
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withOpacity(0.85),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.22),
              blurRadius: 10,
              spreadRadius: 1,
            )
          ],
        ),
      ),
    );
  }

  Widget _iconChip({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.80),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.black.withOpacity(0.06)),
          ),
          child: Tooltip(
            message: tooltip,
            child: Icon(icon, size: 18, color: Colors.black.withOpacity(0.75)),
          ),
        ),
      ),
    );
  }

  Widget _canvasFullscreenOverlay(BubbleSessionController c) {
    return Positioned.fill(
      child: Material(
        color: Colors.black.withOpacity(0.60),
        child: SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              color: Colors.white,
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('Canvas', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      ),
                      _iconChip(
                        icon: Icons.close,
                        tooltip: 'Close',
                        onTap: () => setState(() => _canvasFullscreen = false),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: _canvasCard(c),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _badgeCard(BubbleSessionController c) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _badgeCtrl,
                decoration: InputDecoration(
                  hintText: '“Open to Network”, “Just Chilling”…',
                  filled: true,
                  fillColor: _softField,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _pillButton(
              label: 'Set',
              icon: Icons.check_circle_outline,
              primary: true,
              onPressed: () async {
                final v = _badgeCtrl.text.trim();
                _badgeCtrl.clear();
                await c.setBadge(v);
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        ValueListenableBuilder(
          valueListenable: c.badgesByPeer,
          builder: (_, map, __) {
            final m = map as Map<String, dynamic>;
            if (m.isEmpty) {
              return Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'No active badges.',
                  style: TextStyle(color: Colors.black.withOpacity(0.55), fontWeight: FontWeight.w700),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final e in m.entries)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    decoration: BoxDecoration(
                      color: _softField,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.black.withOpacity(0.06)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(color: _brandGreen.withOpacity(0.85), shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            e.value.label.toString(),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _shortId(e.key),
                          style: TextStyle(fontWeight: FontWeight.w800, color: Colors.black.withOpacity(0.45)),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  String _shortId(String s) => s.length <= 8 ? s : '${s.substring(0, 8)}…';

  Widget _clipboardCard(BubbleSessionController c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 120,
              child: TextField(
                controller: _clipToPeerCtrl,
                decoration: InputDecoration(
                  hintText: 'Peer id',
                  filled: true,
                  fillColor: _softField,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _clipTextCtrl,
                decoration: InputDecoration(
                  hintText: 'URL / snippet (direct beam)',
                  filled: true,
                  fillColor: _softField,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _pillButton(
              label: 'Beam',
              icon: Icons.near_me_outlined,
              primary: true,
              onPressed: () async {
                final to = _clipToPeerCtrl.text.trim();
                final t = _clipTextCtrl.text.trim();
                _clipTextCtrl.clear();

                if (to.isEmpty || to == '*') {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Clipboard is direct-only. Paste a peer id.')),
                  );
                  return;
                }
                if (t.isEmpty) return;

                await c.pushClipboard(toPeerId: to, text: t);
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(child: Text('Inbox', style: TextStyle(fontWeight: FontWeight.w900))),
            Text('5m', style: TextStyle(color: Colors.black.withOpacity(0.55), fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder(
          valueListenable: c.clipboardInbox,
          builder: (_, list, __) {
            final items = list as List;
            if (items.isEmpty) {
              return Text(
                'No clipboard items received.',
                style: TextStyle(color: Colors.black.withOpacity(0.55), fontWeight: FontWeight.w700),
              );
            }

            return Column(
              children: [
                for (final it in items)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.black.withOpacity(0.06)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _contentIcon(it.text.toString()),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text((it.fromName ?? 'Peer').toString(), style: const TextStyle(fontWeight: FontWeight.w900)),
                              const SizedBox(height: 2),
                              Text(
                                it.text.toString(),
                                style: TextStyle(color: Colors.black.withOpacity(0.70), fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _contentIcon(String text) {
    final u = _tryParseUrl(text);

    IconData icon = Icons.text_snippet_outlined;
    Color col = Colors.black.withOpacity(0.65);

    if (u != null) {
      final host = u.host.toLowerCase();
      if (host.contains('youtube') || host.contains('youtu.be')) {
        icon = Icons.play_circle_outline;
        col = _liveRed.withOpacity(0.85);
      } else if (host.contains('google')) {
        icon = Icons.search;
        col = _brandGreen.withOpacity(0.85);
      } else if (host.contains('github')) {
        icon = Icons.code;
        col = Colors.black.withOpacity(0.75);
      } else if (host.contains('instagram')) {
        icon = Icons.camera_alt_outlined;
        col = Colors.purple.withOpacity(0.75);
      } else if (host.contains('x.com') || host.contains('twitter')) {
        icon = Icons.alternate_email;
        col = Colors.blueGrey.withOpacity(0.75);
      } else {
        icon = Icons.link;
        col = _brandGreen.withOpacity(0.75);
      }
    }

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: col.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Icon(icon, color: col),
    );
  }

  Uri? _tryParseUrl(String text) {
    final t = text.trim();
    if (!t.startsWith('http://') && !t.startsWith('https://')) return null;
    try {
      final u = Uri.parse(t);
      return u.hasAuthority ? u : null;
    } catch (_) {
      return null;
    }
  }

  Widget _pillButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    bool primary = false,
  }) {
    final bg = primary ? _brandGreen : Colors.black.withOpacity(0.06);
    final fg = primary ? Colors.white : Colors.black.withOpacity(0.80);

    return SizedBox(
      height: 44,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
    );
  }

  Widget _colorDot(Color c, {required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black12),
          boxShadow: [
            BoxShadow(
              color: c.withOpacity(0.22),
              blurRadius: 14,
              spreadRadius: 1,
            )
          ],
        ),
      ),
    );
  }
}

class _CanvasPainter extends CustomPainter {
  final List<CanvasStroke> strokes;
  final List<Offset> current;
  final Color currentColor;
  final double currentWidth;
  final bool eraser;

  _CanvasPainter({
    required this.strokes,
    required this.current,
    required this.currentColor,
    required this.currentWidth,
    required this.eraser,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFFF7F8F7);
    canvas.drawRect(Offset.zero & size, bg);

    for (final s in strokes) {
      final col = s.colorValue == Colors.transparent.value ? const Color(0xFFF7F8F7) : Color(s.colorValue);
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = s.width
        ..color = col;
      _drawPath(canvas, s.points, p);
    }

    if (current.length >= 2) {
      final col = eraser ? const Color(0xFFF7F8F7) : currentColor;
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = currentWidth
        ..color = col;
      _drawPath(canvas, current, p);
    }
  }

  void _drawPath(Canvas canvas, List<Offset> pts, Paint paint) {
    final path = ui.Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter oldDelegate) {
    return oldDelegate.strokes != strokes ||
        oldDelegate.current != current ||
        oldDelegate.currentColor != currentColor ||
        oldDelegate.currentWidth != currentWidth ||
        oldDelegate.eraser != eraser;
  }
}