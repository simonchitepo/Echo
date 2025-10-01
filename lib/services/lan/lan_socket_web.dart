import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/html.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class LanSocketClient {
  WebSocketChannel? _ch;
  StreamSubscription? _sub;

  final _incomingCtrl = StreamController<String>.broadcast();
  Stream<String> get incoming => _incomingCtrl.stream;

  Future<void> connect({required String host, required int port}) async {
    await dispose();

    final uri = Uri.parse('ws://$host:$port/');
    _ch = HtmlWebSocketChannel.connect(uri);

    _sub = _ch!.stream.listen(
          (data) {
        final text = data is String ? data : jsonEncode(data);
        _incomingCtrl.add(text);
      },
      onDone: () {},
      onError: (_) {},
      cancelOnError: true,
    );
  }

  Future<void> send(String text) async {
    final ch = _ch;
    if (ch == null) return;
    try {
      ch.sink.add(text);
    } catch (_) {}
  }

  Future<void> dispose() async {
    try {
      await _sub?.cancel();
    } catch (_) {}
    _sub = null;

    try {
      await _ch?.sink.close();
    } catch (_) {}
    _ch = null;
  }
}

// Web cannot host
class LanIncoming {
  final String peerId;
  final String text;
  const LanIncoming({required this.peerId, required this.text});
}

class LanSocketServer {
  LanSocketServer({required int port});
  Stream<LanIncoming> get incoming => const Stream.empty();
  Future<void> start() async => throw UnsupportedError('Web cannot host LanSocketServer');
  void broadcast(String text, {String? exceptPeerId}) {}
  void send(String peerId, String text) {}
  Future<void> dispose() async {}
}