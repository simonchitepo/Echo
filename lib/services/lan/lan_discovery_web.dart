import 'dart:async';

class LanBubbleAnnouncement {
  final String hostString;
  final int port;
  final String bubbleId;
  final String displayName;
  final DateTime lastSeen;

  const LanBubbleAnnouncement({
    required this.hostString,
    required this.port,
    required this.bubbleId,
    required this.displayName,
    required this.lastSeen,
  });
}

class LanDiscovery {
  Stream<List<LanBubbleAnnouncement>> get stream => const Stream.empty();
  bool get isListening => false;
  bool get isBroadcasting => false;

  Future<void> startListening() async {}
  Future<void> stopListening() async {}

  Future<void> startBroadcasting({
    required String bubbleId,
    required String displayName,
    required int port,
  }) async {
    // Web browsers can’t do UDP broadcast.
    throw UnsupportedError('LAN discovery not supported on Web.');
  }

  Future<void> stopBroadcasting() async {}
  Future<void> dispose() async {}
}