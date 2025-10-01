class KeptContact {
  final String id;
  final String displayName;
  final DateTime keptAt;
  final String? phone;
  final String? handle;

  const KeptContact({
    required this.id,
    required this.displayName,
    required this.keptAt,
    this.phone,
    this.handle,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'keptAt': keptAt.toIso8601String(),
        'phone': phone,
        'handle': handle,
      };

  static KeptContact fromJson(Map<String, dynamic> json) => KeptContact(
        id: json['id'] as String,
        displayName: json['displayName'] as String,
        keptAt: DateTime.parse(json['keptAt'] as String),
        phone: json['phone'] as String?,
        handle: json['handle'] as String?,
      );
}
