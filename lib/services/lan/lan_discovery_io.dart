import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../platform_info.dart';
import 'android_multicast_lock.dart';

class LanBubbleAnnouncement {
  final InternetAddress host;
  final int port;
  final String bubbleId;
  final String displayName;
  final DateTime lastSeen;

  const LanBubbleAnnouncement({
    required this.host,
    required this.port,
    required this.bubbleId,
    required this.displayName,
    required this.lastSeen,
  });

  String get hostString => host.address;
}

class LanDiscovery {
  static const int discoveryPort = 4041;
  static const Duration beaconInterval = Duration(milliseconds: 900);
  static const Duration ttl = Duration(seconds: 4);

  RawDatagramSocket? _rx;
  RawDatagramSocket? _tx;
  Timer? _beaconTimer;
  Timer? _cleanupTimer;

  final _announcements = <String, LanBubbleAnnouncement>{};
  final _streamCtrl = StreamController<List<LanBubbleAnnouncement>>.broadcast();
  Stream<List<LanBubbleAnnouncement>> get stream => _streamCtrl.stream;

  bool get isListening => _rx != null;
  bool get isBroadcasting => _beaconTimer != null;

  String? _cachedHostIpV4;

  Future<void> startListening() async {
    if (_rx != null) return;

    // ✅ CRITICAL: on Android, acquire multicast lock so UDP broadcast beacons are delivered.
    if (isAndroid) {
      await AndroidMulticastLock.acquire();
    }

    final rx = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      discoveryPort,
      reuseAddress: true,
      reusePort: false,
    );

    rx.broadcastEnabled = true;
    _rx = rx;

    rx.listen((evt) {
      if (evt != RawSocketEvent.read) return;
      final dg = rx.receive();
      if (dg == null) return;

      final sender = dg.address;
      if (sender.type != InternetAddressType.IPv4) return;

      final text = utf8.decode(dg.data, allowMalformed: true);
      Map<String, dynamic> map;
      try {
        final decoded = jsonDecode(text);
        if (decoded is! Map<String, dynamic>) return;
        map = decoded;
      } catch (_) {
        return;
      }

      if (map['type'] != 'echo_bubble') return;

      final bubbleId = (map['bubbleId'] as String?)?.trim();
      final name = (map['displayName'] as String?)?.trim();
      final port = map['port'];

      if (bubbleId == null || bubbleId.isEmpty) return;
      if (name == null || name.isEmpty) return;
      if (port is! int || port <= 0 || port > 65535) return;

      // ✅ Prefer explicit advertised host (fixes Windows virtual adapter issues)
      InternetAddress hostAddr = sender;
      final hostStr = (map['host'] as String?)?.trim();
      if (hostStr != null && hostStr.isNotEmpty) {
        try {
          hostAddr = InternetAddress(hostStr);
        } catch (_) {
          hostAddr = sender;
        }
      }

      final key = '${hostAddr.address}:$port:$bubbleId';
      _announcements[key] = LanBubbleAnnouncement(
        host: hostAddr,
        port: port,
        bubbleId: bubbleId,
        displayName: name,
        lastSeen: DateTime.now(),
      );

      _emit();
    });

    _cleanupTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      final before = _announcements.length;
      _announcements.removeWhere((_, a) => now.difference(a.lastSeen) > ttl);
      if (_announcements.length != before) _emit();
    });

    _emit();
  }

  Future<void> stopListening() async {
    final rx = _rx;
    _rx = null;
    try {
      rx?.close();
    } catch (_) {}

    if (_rx == null && _beaconTimer == null) {
      _cleanupTimer?.cancel();
      _cleanupTimer = null;
    }

    _announcements.clear();
    _emit();

    // ✅ release lock when we no longer need it
    if (isAndroid && !isBroadcasting) {
      await AndroidMulticastLock.release();
    }
  }

  Future<void> startBroadcasting({
    required String bubbleId,
    required String displayName,
    required int port,
  }) async {
    await startListening();

    _tx ??= await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
      reuseAddress: true,
      reusePort: false,
    )..broadcastEnabled = true;

    _cachedHostIpV4 = await _pickBestHostIpV4();
    final subnetBroadcast = _cachedHostIpV4 == null ? null : _subnetBroadcastOf(_cachedHostIpV4!);

    _beaconTimer?.cancel();
    _beaconTimer = Timer.periodic(beaconInterval, (_) {
      final payload = jsonEncode({
        'type': 'echo_bubble',
        'bubbleId': bubbleId,
        'displayName': displayName,
        'port': port,
        'host': _cachedHostIpV4, // ✅ the IP clients should connect to
        'ts': DateTime.now().toIso8601String(),
      });

      final data = utf8.encode(payload);

      // Global broadcast
      _tx?.send(data, InternetAddress('255.255.255.255'), discoveryPort);

      // Subnet broadcast (often more reliable)
      if (subnetBroadcast != null) {
        _tx?.send(data, InternetAddress(subnetBroadcast), discoveryPort);
      }
    });
  }

  Future<void> stopBroadcasting() async {
    _beaconTimer?.cancel();
    _beaconTimer = null;

    try {
      _tx?.close();
    } catch (_) {}
    _tx = null;

    _cachedHostIpV4 = null;

    if (_rx == null) {
      _cleanupTimer?.cancel();
      _cleanupTimer = null;
    }

    // ✅ release lock when no longer needed
    if (isAndroid && !isListening) {
      await AndroidMulticastLock.release();
    }
  }

  Future<void> dispose() async {
    await stopBroadcasting();
    await stopListening();
    await _streamCtrl.close();
  }

  void _emit() {
    final list = _announcements.values.toList()
      ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    _streamCtrl.add(list);
  }

  Future<String?> _pickBestHostIpV4() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );

    bool isBadInterfaceName(String name) {
      final n = name.toLowerCase();
      return n.contains('virtual') ||
          n.contains('vmware') ||
          n.contains('vbox') ||
          n.contains('hyper-v') ||
          n.contains('loopback') ||
          n.contains('tunnel') ||
          n.contains('tap') ||
          n.contains('vpn');
    }

    int scoreInterface(NetworkInterface iface) {
      final n = iface.name.toLowerCase();
      if (isBadInterfaceName(n)) return -100;
      if (n.contains('wi-fi') || n == 'wifi' || n.contains('wlan')) return 50;
      if (n.contains('ethernet') || n.contains('lan')) return 40;
      return 10;
    }

    final sorted = interfaces.toList()
      ..sort((a, b) => scoreInterface(b).compareTo(scoreInterface(a)));

    String? firstFallback;
    for (final iface in sorted) {
      for (final addr in iface.addresses) {
        final ip = addr.address;
        if (ip.startsWith('169.254.')) continue;
        firstFallback ??= ip;
        if (!isBadInterfaceName(iface.name)) return ip;
      }
    }
    return firstFallback;
  }

  String? _subnetBroadcastOf(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    return '${parts[0]}.${parts[1]}.${parts[2]}.255';
  }
}