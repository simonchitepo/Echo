import 'dart:async';

class EchoNsdServiceInfo {
  final String name;
  final String? host;
  final int? port;
  final Map<String, String> txt;

  EchoNsdServiceInfo({
    required this.name,
    required this.host,
    required this.port,
    required this.txt,
  });
}

/// Web / unsupported platforms: no-op.
class EchoNsd {
  final _foundCtrl = StreamController<EchoNsdServiceInfo>.broadcast();
  Stream<EchoNsdServiceInfo> get foundStream => _foundCtrl.stream;

  Future<void> advertise({
    required String instanceName,
    required String serviceType,
    required int port,
    Map<String, String>? txt,
  }) async {}

  Future<void> stopAdvertise() async {}

  Future<void> startDiscovery({required String serviceType}) async {}

  Future<void> stopDiscovery() async {}

  Future<void> dispose() async {
    await _foundCtrl.close();
  }
}