import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/chat_message.dart';
import '../models/peer_profile.dart';
import '../services/echo_comms.dart';

class ChatPage extends StatefulWidget {
  final EchoComms nearby;
  final PeerProfile peer;
  final List<ChatMessage> initialMessages;

  const ChatPage({
    super.key,
    required this.nearby,
    required this.peer,
    this.initialMessages = const <ChatMessage>[],
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {

  static const Color _bg = Colors.white;
  static const Color _green = Color(0xFF0F9D58);
  static const Color _otherBubble = Color(0xFFF2F4F2);

  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  final List<ChatMessage> _msgs = [];
  StreamSubscription<ChatMessage>? _sub;

  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _msgs.addAll(widget.initialMessages);

    _sub = widget.nearby.messagesStream.listen((m) {
      if (!mounted) return;
      if (m.peerId != widget.peer.endpointId) return;

      setState(() => _msgs.add(m));
      _jumpToBottomSoon();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    _inputCtrl.clear();

    try {
      await widget.nearby.sendMessage(widget.peer.endpointId, text);
      _jumpToBottomSoon();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _jumpToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
  }

  void _jumpToBottom() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.animateTo(
      _scrollCtrl.position.maxScrollExtent + 140,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  String _formatTime(DateTime ts) {
    final h = ts.hour.toString().padLeft(2, '0');
    final m = ts.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  ImageProvider? _peerAvatarProvider() {
    final b64 = widget.peer.profileImageB64;
    if (b64 == null || b64.trim().isEmpty) return null;
    try {
      return MemoryImage(base64Decode(b64.trim()));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final avatar = _peerAvatarProvider();

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),

        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFFF7F8F7),
              backgroundImage: avatar,
              child: avatar == null
                  ? Text(
                widget.peer.displayName.isEmpty
                    ? '?'
                    : widget.peer.displayName.characters.first.toUpperCase(),
                style: TextStyle(
                  color: Colors.black.withOpacity(0.75),
                  fontWeight: FontWeight.w900,
                ),
              )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.peer.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Nearby',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.primary.withOpacity(0.85),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        actions: [
          if ((widget.peer.phone != null && widget.peer.phone!.trim().isNotEmpty) ||
              (widget.peer.handle != null && widget.peer.handle!.trim().isNotEmpty))
            PopupMenuButton<String>(
              tooltip: 'Contact info',
              onSelected: (v) async {
                if (v == 'copy_phone' && widget.peer.phone != null) {
                  await Clipboard.setData(ClipboardData(text: widget.peer.phone!.trim()));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('Phone copied')));
                  }
                }
                if (v == 'copy_handle' && widget.peer.handle != null) {
                  await Clipboard.setData(ClipboardData(text: widget.peer.handle!.trim()));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('Handle copied')));
                  }
                }
              },
              itemBuilder: (_) => [
                if (widget.peer.phone != null && widget.peer.phone!.trim().isNotEmpty)
                  const PopupMenuItem(value: 'copy_phone', child: Text('Copy phone')),
                if (widget.peer.handle != null && widget.peer.handle!.trim().isNotEmpty)
                  const PopupMenuItem(value: 'copy_handle', child: Text('Copy handle')),
              ],
              icon: const Icon(Icons.contact_page_outlined),
            ),
        ],
      ),
      body: Column(
        children: [
          const _SystemLine(text: 'Only people who are here, right now.'),

          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              itemCount: _msgs.length,
              itemBuilder: (context, i) {
                final m = _msgs[i];
                return _MessageRow(
                  text: m.text,
                  time: _formatTime(m.at),
                  isMe: m.fromMe,
                );
              },
            ),
          ),

          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: _Composer(
                controller: _inputCtrl,
                enabled: !_sending,
                onSend: _send,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SystemLine extends StatelessWidget {
  final String text;
  const _SystemLine({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F8F7),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF64748B),
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  static const Color _green = Color(0xFF0F9D58);
  static const Color _otherBubble = Color(0xFFF2F4F2);

  final String text;
  final String time;
  final bool isMe;

  const _MessageRow({
    required this.text,
    required this.time,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final bubbleColor = isMe ? _green : _otherBubble;
    final textColor = isMe ? Colors.white : Colors.black.withOpacity(0.88);

    final radius = BorderRadius.only(
      topLeft: Radius.circular(isMe ? 18 : 10),
      topRight: Radius.circular(isMe ? 10 : 18),
      bottomLeft: const Radius.circular(18),
      bottomRight: const Radius.circular(18),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: radius,
                  ),
                  child: Text(
                    text,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  time,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6B7280),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;

  const _Composer({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            enabled: enabled,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend(),
            decoration: InputDecoration(
              hintText: 'Message...',
              filled: true,
              fillColor: const Color(0xFFF7F8F7),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 50,
          width: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F9D58),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            onPressed: enabled ? onSend : null,
            child: const Icon(Icons.send),
          ),
        ),
      ],
    );
  }
}