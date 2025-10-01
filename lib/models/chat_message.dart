import 'dart:convert';

class ChatMessage {
  final String peerId;
  final bool fromMe;
  final String text;
  final DateTime at;
  final String messageId;
  final String bubbleId;
  final String fromPeerId;
  final String toPeerId;
  final String? fromName;
  final String? transport;

  const ChatMessage({
    required this.peerId,
    required this.fromMe,
    required this.text,
    required this.at,
    required this.messageId,
    required this.bubbleId,
    required this.fromPeerId,
    required this.toPeerId,
    this.fromName,
    this.transport,
  });

  ChatMessage copyWith({
    String? peerId,
    bool? fromMe,
    String? text,
    DateTime? at,
    String? messageId,
    String? bubbleId,
    String? fromPeerId,
    String? toPeerId,
    String? fromName,
    String? transport,
  }) {
    return ChatMessage(
      peerId: peerId ?? this.peerId,
      fromMe: fromMe ?? this.fromMe,
      text: text ?? this.text,
      at: at ?? this.at,
      messageId: messageId ?? this.messageId,
      bubbleId: bubbleId ?? this.bubbleId,
      fromPeerId: fromPeerId ?? this.fromPeerId,
      toPeerId: toPeerId ?? this.toPeerId,
      fromName: fromName ?? this.fromName,
      transport: transport ?? this.transport,
    );
  }

  Map<String, dynamic> toJson() => {
    'peerId': peerId,
    'fromMe': fromMe,
    'text': text,
    'at': at.toIso8601String(),
    'messageId': messageId,
    'bubbleId': bubbleId,
    'fromPeerId': fromPeerId,
    'toPeerId': toPeerId,
    'fromName': fromName,
    'transport': transport,
  };

  static ChatMessage fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      peerId: (json['peerId'] as String?) ?? '',
      fromMe: (json['fromMe'] as bool?) ?? false,
      text: (json['text'] as String?) ?? '',
      at: DateTime.tryParse((json['at'] as String?) ?? '') ?? DateTime.now(),
      messageId: (json['messageId'] as String?) ?? '',
      bubbleId: (json['bubbleId'] as String?) ?? '',
      fromPeerId: (json['fromPeerId'] as String?) ?? '',
      toPeerId: (json['toPeerId'] as String?) ?? '',
      fromName: json['fromName'] as String?,
      transport: json['transport'] as String?,
    );
  }


  String toJsonString() => jsonEncode(toJson());
  static ChatMessage? tryFromJsonString(String s) {
    try {
      final v = jsonDecode(s);
      if (v is Map<String, dynamic>) return fromJson(v);
      return null;
    } catch (_) {
      return null;
    }
  }
}