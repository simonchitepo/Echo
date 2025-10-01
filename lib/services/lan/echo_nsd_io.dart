import 'dart:async';
import 'dart:convert';
import 'dart:io';

class EchoNsdServiceInfo {
  final String name;
  final String? host;
  final int? port;
  final Map<String, String> txt;

  const EchoNsdServiceInfo({
    required this.name,
    required this.host,
    required this.port,
    required this.txt,
  });
}

/// Pure-Dart LAN discovery using UDP broadcast.
/// Replaces Bonsoir/mDNS to avoid native Windows plugin issues.
///
/// Host advertises:
///  - sends UDP broadcast every ~2s to port 4041
///
/// Clients discover:
///  - listen on UDP 4041 and emit foundStream when packets match serviceType
///
/// IMPORTANT WINDOWS NOTE:
///  - `reusePort` is NOT supported on Windows. Never pass reusePort on Windows.
///    Otherwise you'll get: "reusePort not supported for Windows" and discovery can fail.
class EchoNsd {
  static const int _discoveryPort = 4041;
  static final InternetAddress _broadcastAddr = InternetAddress('255.255.255.255');

  RawDatagramSocket? _advSocket;
  Timer? _advTimer;

  RawDatagramSocket? _rxSocket;
  StreamSubscription? _rxSub;

  final _foundCtrl = StreamController<EchoNsdServiceInfo>.broadcast();
  Stream<EchoNsdServiceInfo> get foundStream => _foundCtrl.stream;

  bool _disposed = false;

  Map<String, dynamic>? _advPayload;

  // -----------------------
  // Advertising
  // -----------------------
  Future<void> advertise({
    required String instanceName,
    required String serviceType,
    required int port,
    Map<String, String> txt = const {},
  }) async {
    _ensureNotDisposed();
    await stopAdvertise();

    // We include txt + serviceType + port. Host is derived by receiver from sender IP.
    _advPayload = <String, dynamic>{
      'v': 1,
      'serviceType': serviceType,
      'name': instanceName,
      'port': port,
      'txt': txt,
      'ts': DateTime.now().toIso8601String(),
    };

    // ✅ FIX: do NOT pass reusePort on Windows
    if (Platform.isWindows) {
      _advSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );
    } else {
      _advSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
        reusePort: true,
      );
    }

    _advSocket!.broadcastEnabled = true;

    // Send immediately + every 2 seconds
    _sendBeacon();
    _advTimer = Timer.periodic(const Duration(seconds: 2), (_) => _sendBeacon());
  }

  void _sendBeacon() {
    final sock = _advSocket;
    final payload = _advPayload;
    if (sock == null || payload == null) return;

    payload['ts'] = DateTime.now().toIso8601String();

    final bytes = utf8.encode(jsonEncode(payload));
    try {
      sock.send(bytes, _broadcastAddr, _discoveryPort);
    } catch (_) {
      // ignore send failures (network changes / firewall etc.)
    }
  }

  Future<void> stopAdvertise() async {
    _advTimer?.cancel();
    _advTimer = null;

    try {
      _advSocket?.close();
    } catch (_) {}
    _advSocket = null;

    _advPayload = null;
  }

  // -----------------------
  // Discovery
  // -----------------------
  Future<void> startDiscovery({required String serviceType}) async {
    _ensureNotDisposed();
    await stopDiscovery();

    // ✅ FIX: do NOT pass reusePort on Windows
    if (Platform.isWindows) {
      _rxSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _discoveryPort,
        reuseAddress: true,
      );
    } else {
      _rxSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _discoveryPort,
        reuseAddress: true,
        reusePort: true,
      );
    }

    // Doesn’t hurt; some stacks behave better with it enabled.
    _rxSocket!.broadcastEnabled = true;

    _rxSub = _rxSocket!.listen((event) {
      if (event != RawSocketEvent.read) return;

      Datagram? dg;
      while ((dg = _rxSocket!.receive()) != null) {
        _handleDatagram(dg!, serviceType);
      }
    });
  }

  void _handleDatagram(Datagram dg, String expectedServiceType) {
    final senderHost = dg.address.address;

    Map<String, dynamic> map;
    try {
      final s = utf8.decode(dg.data);
      final v = jsonDecode(s);
      if (v is! Map<String, dynamic>) return;
      map = v;
    } catch (_) {
      return;
    }

    final st = (map['serviceType'] ?? '').toString().trim();
    if (st.isEmpty || st != expectedServiceType) return;

    final name = (map['name'] ?? 'echo').toString();
    final portAny = map['port'];
    final port = portAny is int ? portAny : int.tryParse(portAny?.toString() ?? '');

    final txtAny = map['txt'];
    final txt = <String, String>{};
    if (txtAny is Map) {
      for (final e in txtAny.entries) {
        txt[e.key.toString()] = e.value.toString();
      }
    }

    // Must have bubbleId to be useful
    final bubbleId = (txt['bubbleId'] ?? '').trim();
    if (bubbleId.isEmpty) return;

    _foundCtrl.add(EchoNsdServiceInfo(
      name: name,
      host: senderHost,
      port: port,
      txt: txt,
    ));
  }

  Future<void> stopDiscovery() async {
    await _rxSub?.cancel();
    _rxSub = null;

    try {
      _rxSocket?.close();
    } catch (_) {}
    _rxSocket = null;
  }

  // -----------------------
  // Dispose
  // -----------------------
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    await stopAdvertise();
    await stopDiscovery();

    await _foundCtrl.close();
  }

  void _ensureNotDisposed() {
    if (_disposed) throw StateError('EchoNsd is disposed.');
  }
}