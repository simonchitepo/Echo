import 'dart:async';

class LanDiscoveredHost {
  final String host;
  final int port;
  final String peerId;
  final String bubbleId;
  final String displayName;

  LanDiscoveredHost({
    required this.host,
    required this.port,
    required this.peerId,
    required this.bubbleId,
    required this.displayName,
  });
}

/// No-op discovery for platforms where LAN discovery is not available (e.g. Web).
class LanDiscovery {
  final _ctrl = StreamController<LanDiscoveredHost>.broadcast();
  Stream<LanDiscoveredHost> get foundStream => _ctrl.stream;

  Future<void> start({
    required String instanceName,
    required int port,
    required Map<String, String> txt,
  }) async {
    // no-op
  }

  Future<void> stop() async {
    await _ctrl.close();
  }
}