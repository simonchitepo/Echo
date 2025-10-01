class BubbleShout {
  final String text;
  final String fromPeerId;
  final String? fromName;
  final DateTime createdAt;
  final DateTime expiresAt;

  const BubbleShout({
    required this.text,
    required this.fromPeerId,
    required this.createdAt,
    required this.expiresAt,
    this.fromName,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  Duration get remaining => expiresAt.difference(DateTime.now());
}