import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// UDP broadcast beacon (mDNS/NSD fallback).
///
/// Host: periodically broadcasts bubble presence on LAN.
/// Client: listens for beacons and reports discovered bubbles.
///
/// Uses UDP port 4041 by default (separate from WS port 4040).
class LanBeacon {
  static const int defaultBeaconPort = 4041;

  final int beaconPort;
  LanBeacon({this.beaconPort = defaultBeaconPort});

  RawDatagramSocket? _sock;
  Timer? _txTimer;

  final _rxCtrl = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get incoming => _rxCtrl.stream;

  Future<void> startListener() async {
    if (_sock != null) return;

    // Bind to any IPv4 and allow broadcasts.
    final sock = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      beaconPort,
      reuseAddress: true,
      // reusePort is not supported on Windows (and not needed here).
    );
    sock.broadcastEnabled = true;

    _sock = sock;
    sock.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = sock.receive();
      if (dg == null) return;

      try {
        final text = utf8.decode(dg.data);
        final obj = jsonDecode(text);
        if (obj is Map<String, dynamic>) {
          // Add sender IP if not present
          obj.putIfAbsent('host', () => dg.address.address);
          _rxCtrl.add(obj);
        }
      } catch (_) {
        // ignore invalid packets
      }
    });
  }

  Future<void> startBroadcaster({
    required String bubbleId,
    required String displayName,
    required String peerId,
    required int wsPort,
  }) async {
    // Ensure socket exists
    if (_sock == null) {
      final sock = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0, // ephemeral source port for sending
        reuseAddress: true,
      );
      sock.broadcastEnabled = true;
      _sock = sock;
    }

    // Broadcast every 2s
    _txTimer?.cancel();
    _txTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final pkt = <String, dynamic>{
        'type': 'echo_beacon',
        'v': 1,
        'bubbleId': bubbleId,
        'displayName': displayName,
        'peerId': peerId,
        'wsPort': wsPort,
        'ts': DateTime.now().toIso8601String(),
      };
      final data = utf8.encode(jsonEncode(pkt));

      // LAN broadcast
      _sock?.send(
        data,
        InternetAddress('255.255.255.255'),
        beaconPort,
      );
    });
  }

  Future<void> stopBroadcaster() async {
    _txTimer?.cancel();
    _txTimer = null;
  }

  Future<void> dispose() async {
    await stopBroadcaster();
    try {
      _sock?.close();
    } catch (_) {}
    _sock = null;

    try {
      await _rxCtrl.close();
    } catch (_) {}
  }
}