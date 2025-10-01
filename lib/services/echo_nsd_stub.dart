import 'dart:async';

class EchoNsdServiceInfo {
  final String name;
  final String type;
  final String? host;
  final int? port;
  final Map<String, String> txt;

  EchoNsdServiceInfo({
    required this.name,
    required this.type,
    required this.host,
    required this.port,
    required this.txt,
  });
}

class EchoNsd {
  Stream<EchoNsdServiceInfo> get foundStream => const Stream.empty();

  Future<void> startDiscovery({required String serviceType}) async {}

  Future<void> stopDiscovery() async {}

  Future<void> advertise({
    required String instanceName,
    required String serviceType,
    required int port,
    required Map<String, String> txt,
  }) async {}

  Future<void> stopAdvertise() async {}

  Future<void> dispose() async {}
}