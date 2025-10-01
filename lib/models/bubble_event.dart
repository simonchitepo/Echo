import 'dart:convert';

class BubbleEvent {
  final String eventId;
  final String bubbleId;
  final String kind;
  final Map<String, dynamic> data;
  final String fromPeerId;
  final String? fromName;
  final String toPeerId;
  final DateTime ts;
  final int? ttlSeconds;
  final String? transport;

  const BubbleEvent({
    required this.eventId,
    required this.bubbleId,
    required this.kind,
    required this.data,
    required this.fromPeerId,
    required this.toPeerId,
    required this.ts,
    this.fromName,
    this.ttlSeconds,
    this.transport,
  });

  Map<String, dynamic> toJson() => {
    'type': 'event',
    'eventId': eventId,
    'bubbleId': bubbleId,
    'kind': kind,
    'data': data,
    'fromPeerId': fromPeerId,
    'from': fromName,
    'toPeerId': toPeerId,
    'ts': ts.toIso8601String(),
    'ttlSeconds': ttlSeconds,
    'transport': transport,
  };

  static BubbleEvent? tryFromJson(Map<String, dynamic> json) {
    try {
      final type = (json['type'] as String?)?.trim();
      if (type != 'event') return null;

      final eventId = (json['eventId'] as String?)?.trim();
      final bubbleId = (json['bubbleId'] as String?)?.trim();
      final kind = (json['kind'] as String?)?.trim();
      final fromPeerId = (json['fromPeerId'] as String?)?.trim();
      final toPeerId = (json['toPeerId'] as String?)?.trim() ?? '*';
      final ts = DateTime.tryParse((json['ts'] as String?) ?? '');

      final rawData = json['data'];
      if (eventId == null || eventId.isEmpty) return null;
      if (bubbleId == null || bubbleId.isEmpty) return null;
      if (kind == null || kind.isEmpty) return null;
      if (fromPeerId == null || fromPeerId.isEmpty) return null;
      if (ts == null) return null;
      if (rawData is! Map) return null;

      return BubbleEvent(
        eventId: eventId,
        bubbleId: bubbleId,
        kind: kind,
        data: Map<String, dynamic>.from(rawData as Map),
        fromPeerId: fromPeerId,
        fromName: (json['from'] as String?)?.trim(),
        toPeerId: toPeerId,
        ts: ts,
        ttlSeconds: json['ttlSeconds'] is int ? json['ttlSeconds'] as int : null,
        transport: (json['transport'] as String?)?.trim(),
      );
    } catch (_) {
      return null;
    }
  }

  String toJsonString() => jsonEncode(toJson());

  static BubbleEvent? tryFromJsonString(String s) {
    try {
      final v = jsonDecode(s);
      if (v is Map<String, dynamic>) return tryFromJson(v);
      return null;
    } catch (_) {
      return null;
    }
  }
}