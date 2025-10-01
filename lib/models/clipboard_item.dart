class ClipboardItem {
  final String itemId;
  final String text;
  final String fromPeerId;
  final String? fromName;
  final DateTime createdAt;
  final DateTime expiresAt;

  const ClipboardItem({
    required this.itemId,
    required this.text,
    required this.fromPeerId,
    required this.createdAt,
    required this.expiresAt,
    this.fromName,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}