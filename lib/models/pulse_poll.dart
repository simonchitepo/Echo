class PulsePoll {
  final String pollId;
  final String question;
  final List<String> options;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String createdByPeerId;
  final String? createdByName;
  final List<int> counts;
  final Map<String, int> myVotesByPeer;

  PulsePoll({
    required this.pollId,
    required this.question,
    required this.options,
    required this.createdAt,
    required this.expiresAt,
    required this.createdByPeerId,
    this.createdByName,
    List<int>? counts,
    Map<String, int>? myVotesByPeer,
  })  : counts = counts ?? List<int>.filled(options.length, 0),
        myVotesByPeer = myVotesByPeer ?? <String, int>{};

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  Duration get remaining => expiresAt.difference(DateTime.now());
}