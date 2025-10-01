class BubbleSettings {
  final bool isPrivate;
  final bool requirePassword;
  final String inviteCode;
  final String? password;

  const BubbleSettings({
    required this.isPrivate,
    required this.requirePassword,
    required this.inviteCode,
    this.password,
  });

  BubbleSettings copyWith({
    bool? isPrivate,
    bool? requirePassword,
    String? inviteCode,
    String? password,
  }) {
    return BubbleSettings(
      isPrivate: isPrivate ?? this.isPrivate,
      requirePassword: requirePassword ?? this.requirePassword,
      inviteCode: inviteCode ?? this.inviteCode,
      password: password ?? this.password,
    );
  }

  static BubbleSettings public() =>
      const BubbleSettings(isPrivate: false, requirePassword: false, inviteCode: '', password: null);
}