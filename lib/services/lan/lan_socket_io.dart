import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

class LanIncoming {
  final String peerId;
  final String text;
  const LanIncoming({required this.peerId, required this.text});
}

class LanSocketServer {
  LanSocketServer({required this.port});
  final int port;

  HttpServer? _http;
  bool get isRunning => _http != null;

  final _incomingCtrl = StreamController<LanIncoming>.broadcast();
  Stream<LanIncoming> get incoming => _incomingCtrl.stream;

  final Map<String, WebSocket> _peers = {};
  int _nextId = 1;

  // -------------------------------------------------------
  // START SERVER
  // -------------------------------------------------------
  Future<void> start() async {
    if (_http != null) return;

    try {
      _http = await HttpServer.bind(
        InternetAddress.anyIPv4,
        port,
        shared: !Platform.isWindows, // 🔥 FIX: Windows doesn't support reusePort
      );

      _http!.listen(
        _handleRequest,
        onError: (_) {},
      );

      final addr = _http!.address.address;
      print('[Echo] LAN socket server running on $addr:$port');
    } catch (e) {
      print('[Echo] LAN socket bind failed: $e');
      rethrow;
    }
  }

  // -------------------------------------------------------
  // HANDLE REQUEST
  // -------------------------------------------------------
  Future<void> _handleRequest(HttpRequest req) async {
    if (!WebSocketTransformer.isUpgradeRequest(req)) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }

    try {
      final ws = await WebSocketTransformer.upgrade(req);
      final peerId = 'p${_nextId++}';
      _peers[peerId] = ws;

      // Tell client its assigned peerId
      _sendRaw(peerId, jsonEncode({'type': '_connect', 'peerId': peerId}));

      ws.listen(
            (data) {
          final text = data is String
              ? data
              : utf8.decode(data as List<int>);
          _incomingCtrl.add(LanIncoming(peerId: peerId, text: text));
        },
        onDone: () => _handleDisconnect(peerId),
        onError: (_) => _handleDisconnect(peerId),
        cancelOnError: true,
      );
    } catch (_) {
      try {
        await req.response.close();
      } catch (_) {}
    }
  }

  void _handleDisconnect(String peerId) {
    _peers.remove(peerId);
    _incomingCtrl.add(
      LanIncoming(
        peerId: peerId,
        text: jsonEncode({'type': '_disconnect'}),
      ),
    );
  }

  // -------------------------------------------------------
  // SEND
  // -------------------------------------------------------
  void broadcast(String text, {String? exceptPeerId}) {
    for (final entry in _peers.entries) {
      if (exceptPeerId != null && entry.key == exceptPeerId) continue;
      try {
        entry.value.add(text);
      } catch (_) {}
    }
  }

  void send(String peerId, String text) {
    _sendRaw(peerId, text);
  }

  void _sendRaw(String peerId, String text) {
    final ws = _peers[peerId];
    if (ws == null) return;
    try {
      ws.add(text);
    } catch (_) {}
  }

  // -------------------------------------------------------
  // DISPOSE
  // -------------------------------------------------------
  Future<void> dispose() async {
    try {
      for (final ws in _peers.values) {
        try {
          await ws.close();
        } catch (_) {}
      }
      _peers.clear();
    } catch (_) {}

    try {
      await _http?.close(force: true);
    } catch (_) {}

    _http = null;

    try {
      await _incomingCtrl.close();
    } catch (_) {}
  }
}

// =======================================================
// CLIENT
// =======================================================

class LanSocketClient {
  WebSocketChannel? _ch;
  StreamSubscription? _sub;

  final _incomingCtrl = StreamController<String>.broadcast();
  Stream<String> get incoming => _incomingCtrl.stream;

  Future<void> connect({
    required String host,
    required int port,
  }) async {
    await dispose();

    final uri = Uri.parse('ws://$host:$port/');
    try {
      _ch = IOWebSocketChannel.connect(uri);

      _sub = _ch!.stream.listen(
            (data) {
          final text = data is String
              ? data
              : utf8.decode(data as List<int>);
          _incomingCtrl.add(text);
        },
        onDone: () {},
        onError: (_) {},
        cancelOnError: true,
      );
    } catch (e) {
      print('[Echo] LAN client connect failed: $e');
    }
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