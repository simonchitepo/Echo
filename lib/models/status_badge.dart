class StatusBadge {
  final String label;
  final DateTime setAt;
  final DateTime expiresAt;

  const StatusBadge({
    required this.label,
    required this.setAt,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  Duration get remaining => expiresAt.difference(DateTime.now());
}