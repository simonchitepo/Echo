class PeerProfile {
  final String endpointId;
  final String displayName;
  final String bubbleId;
  final DateTime firstSeen;
  final String? phone;
  final String? handle;
  final String? profileImageB64;

  const PeerProfile({
    required this.endpointId,
    required this.displayName,
    required this.bubbleId,
    required this.firstSeen,
    this.phone,
    this.handle,
    this.profileImageB64,
  });

  Map<String, dynamic> toJson() => {
    'endpointId': endpointId,
    'displayName': displayName,
    'bubbleId': bubbleId,
    'firstSeen': firstSeen.toIso8601String(),
    'phone': phone,
    'handle': handle,
    'profileImageB64': profileImageB64,
  };

  static PeerProfile fromJson(Map<String, dynamic> json) => PeerProfile(
    endpointId: json['endpointId'] as String,
    displayName: json['displayName'] as String,
    bubbleId: json['bubbleId'] as String,
    firstSeen: DateTime.parse(json['firstSeen'] as String),
    phone: json['phone'] as String?,
    handle: json['handle'] as String?,
    profileImageB64: json['profileImageB64'] as String?,
  );
}