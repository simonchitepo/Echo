import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:nearby_connections/nearby_connections.dart';
import 'package:uuid/uuid.dart';

import '../models/bubble_event.dart';
import '../models/peer_profile.dart';
import '../models/chat_message.dart';
import 'echo_comms.dart';
import 'log.dart';

class NearbyService implements EchoComms {
  static const String serviceId = 'com.echo.nearby';

  final Nearby _nearby = Nearby();

  final _peersController = StreamController<List<PeerProfile>>.broadcast();
  @override
  Stream<List<PeerProfile>> get peersStream => _peersController.stream;

  final _messagesController = StreamController<ChatMessage>.broadcast();
  @override
  Stream<ChatMessage> get messagesStream => _messagesController.stream;

  final _eventsController = StreamController<BubbleEvent>.broadcast();
  @override
  Stream<BubbleEvent> get eventsStream => _eventsController.stream;

  final Map<String, PeerProfile> _peersById = {};

  String? _displayName;
  String? _bubbleId;

  String? _myPhone;
  String? _myHandle;
  String? _myProfileImageB64;

  bool _running = false;

  @override
  bool get isRunning => _running;

  /// Optional contact info you can choose to share with people in the bubble.
  @override
  void setMyContactInfo({String? phone, String? handle, String? profileImageB64}) {
    _myPhone = phone?.trim();
    _myHandle = handle?.trim();
    final v = profileImageB64?.trim();
    _myProfileImageB64 = (v == null || v.isEmpty) ? null : v;
  }

  @override
  Future<void> setLanHost(String host, {int port = 4040}) async {
    // No-op: Nearby Connections does not use LAN host.
  }

  @override
  Future<void> start({
    required String displayName,
    required String bubbleId,
    dynamic bubbleSettings, // ignored here (Nearby privacy handled later if you implement it)
  }) async {
    _displayName = displayName;
    _bubbleId = bubbleId;

    if (_running) {
      await stop();
    }
    _running = true;
    _peersById.clear();
    _emitPeers();

    final endpointName = _endpointName(displayName: displayName, bubbleId: bubbleId);

    await _nearby.startAdvertising(
      endpointName,
      Strategy.P2P_CLUSTER,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult: _onConnectionResult,
      onDisconnected: _onDisconnected,
      serviceId: serviceId,
    );

    await _nearby.startDiscovery(
      endpointName,
      Strategy.P2P_CLUSTER,
      onEndpointFound: _onEndpointFound,
      onEndpointLost: (id) {
        logInfo('endpoint lost: $id');
        _peersById.remove(id);
        _emitPeers();
      },
      serviceId: serviceId,
    );

    logInfo('Nearby started. bubbleId=$bubbleId');
  }

  @override
  Future<void> stop() async {
    if (!_running) return;
    _running = false;

    try {
      await _nearby.stopAdvertising();
    } catch (_) {}
    try {
      await _nearby.stopDiscovery();
    } catch (_) {}
    try {
      await _nearby.stopAllEndpoints();
    } catch (_) {}

    _peersById.clear();
    _emitPeers();
    logInfo('Nearby stopped');
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _peersController.close();
    await _messagesController.close();
    await _eventsController.close();
  }

  // -------------------------
  // Outgoing
  // -------------------------

  @override
  Future<void> sendMessage(String endpointId, String text) async {
    final bubbleId = _bubbleId;
    final displayName = _displayName;
    if (bubbleId == null || displayName == null) return;

    final msgId = const Uuid().v4();
    final ts = DateTime.now();

    final msg = jsonEncode({
      'type': 'chat',
      'msgId': msgId,
      'text': text,
      'from': displayName,
      'bubbleId': bubbleId,
      'ts': ts.toIso8601String(),
    });

    final bytes = Uint8List.fromList(utf8.encode(msg));
    await _nearby.sendBytesPayload(endpointId, bytes);

    // emit locally so UI updates instantly
    _messagesController.add(ChatMessage(
      peerId: endpointId,
      fromMe: true,
      text: text,
      at: ts,
      messageId: msgId,
      bubbleId: bubbleId,
      fromPeerId: 'me',
      toPeerId: endpointId,
      fromName: displayName,
      transport: 'nearby',
    ));
  }

  @override
  Future<void> sendEvent(BubbleEvent event, {String toPeerId = '*'}) async {
    final bubbleId = _bubbleId;
    if (bubbleId == null) return;
    if (event.bubbleId != bubbleId) return;

    final packet = jsonEncode({
      'type': 'event',
      ...event.toJson(),
      'toPeerId': toPeerId,
      'transport': 'nearby',
    });

    final bytes = Uint8List.fromList(utf8.encode(packet));

    if (toPeerId == '*' || toPeerId.trim().isEmpty) {
      for (final pid in _peersById.keys) {
        await _nearby.sendBytesPayload(pid, bytes);
      }
    } else {
      await _nearby.sendBytesPayload(toPeerId, bytes);
    }

    // echo locally
    _eventsController.add(event);
  }

  // -------------------------
  // Nearby callbacks
  // -------------------------

  void _onEndpointFound(String id, String name, String foundServiceId) {
    logInfo('endpoint found: $id name=$name');
    final parsed = _parseEndpointName(name);
    if (parsed == null) return;

    final currentBubble = _bubbleId;
    if (currentBubble == null || parsed.bubbleId != currentBubble) return;

    _nearby.requestConnection(
      _displayName ?? 'Echo',
      id,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult: _onConnectionResult,
      onDisconnected: _onDisconnected,
    );
  }

  void _onConnectionInitiated(String id, ConnectionInfo info) {
    logInfo('connection initiated: $id endpointName=${info.endpointName}');

    _nearby.acceptConnection(
      id,
      onPayLoadRecieved: (endpointId, payload) {
        if (payload.type == PayloadType.BYTES) {
          final bytes = payload.bytes;
          if (bytes == null) return;
          _handleBytes(endpointId, bytes);
        }
      },
      onPayloadTransferUpdate: (_, __) {},
    );

    // optimistic peer display
    final parsed = _parseEndpointName(info.endpointName);
    if (parsed != null && parsed.bubbleId == _bubbleId) {
      _peersById[id] = PeerProfile(
        endpointId: id,
        displayName: parsed.displayName,
        bubbleId: parsed.bubbleId,
        firstSeen: DateTime.now(),
      );
      _emitPeers();
    }
  }

  void _onConnectionResult(String id, Status status) {
    logInfo('connection result: $id status=$status');
    if (status == Status.CONNECTED) {
      _sendMyProfile(id);
    } else {
      _peersById.remove(id);
      _emitPeers();
    }
  }

  void _onDisconnected(String id) {
    logInfo('disconnected: $id');
    _peersById.remove(id);
    _emitPeers();
  }

  void _sendMyProfile(String endpointId) {
    final displayName = _displayName;
    final bubbleId = _bubbleId;
    if (displayName == null || bubbleId == null) return;

    final msg = jsonEncode({
      'type': 'profile',
      'displayName': displayName,
      'bubbleId': bubbleId,
      'phone': _myPhone,
      'handle': _myHandle,
      'profileImageB64': _myProfileImageB64,
    });

    final bytes = Uint8List.fromList(utf8.encode(msg));
    _nearby.sendBytesPayload(endpointId, bytes);
  }

  void _handleBytes(String endpointId, Uint8List bytes) {
    try {
      final str = utf8.decode(bytes);
      final jsonMap = jsonDecode(str) as Map<String, dynamic>;
      final type = (jsonMap['type'] as String?)?.trim();

      if (type == 'profile') {
        final name = (jsonMap['displayName'] as String?)?.trim();
        final bubbleId = (jsonMap['bubbleId'] as String?)?.trim();
        final phone = (jsonMap['phone'] as String?)?.trim();
        final handle = (jsonMap['handle'] as String?)?.trim();
        final img = (jsonMap['profileImageB64'] as String?)?.trim();

        if (name == null || name.isEmpty || bubbleId == null || bubbleId.isEmpty) return;
        if (bubbleId != _bubbleId) return;

        _peersById[endpointId] = PeerProfile(
          endpointId: endpointId,
          displayName: name,
          bubbleId: bubbleId,
          firstSeen: _peersById[endpointId]?.firstSeen ?? DateTime.now(),
          phone: (phone == null || phone.isEmpty) ? null : phone,
          handle: (handle == null || handle.isEmpty) ? null : handle,
          profileImageB64: (img == null || img.isEmpty) ? null : img,
        );
        _emitPeers();
        return;
      }

      if (type == 'chat') {
        final bubbleId = (jsonMap['bubbleId'] as String?)?.trim();
        if (bubbleId != _bubbleId) return;

        final text = (jsonMap['text'] as String?)?.trim();
        if (text == null || text.isEmpty) return;

        final msgId = (jsonMap['msgId'] as String?)?.trim() ?? const Uuid().v4();
        final fromName = (jsonMap['from'] as String?)?.trim();
        final ts = DateTime.tryParse((jsonMap['ts'] as String?) ?? '') ?? DateTime.now();

        _messagesController.add(ChatMessage(
          peerId: endpointId,
          fromMe: false,
          text: text,
          at: ts,
          messageId: msgId,
          bubbleId: bubbleId ?? '',
          fromPeerId: endpointId,
          toPeerId: '*',
          fromName: fromName,
          transport: 'nearby',
        ));
        return;
      }

      if (type == 'event') {
        final bubbleId = (jsonMap['bubbleId'] as String?)?.trim();
        if (bubbleId != _bubbleId) return;

        final evt = BubbleEvent.tryFromJson(Map<String, dynamic>.from(jsonMap));
        if (evt != null) _eventsController.add(evt);
        return;
      }
    } catch (e) {
      logInfo('payload parse error: $e');
    }
  }

  void _emitPeers() {
    final peers = _peersById.values.toList()
      ..sort((a, b) => a.firstSeen.compareTo(b.firstSeen));
    _peersController.add(peers);
  }

  String _endpointName({required String displayName, required String bubbleId}) {
    final safeName = displayName.replaceAll('|', ' ').trim();
    return '$safeName|$bubbleId';
  }

  _EndpointInfo? _parseEndpointName(String raw) {
    final parts = raw.split('|');
    if (parts.length < 2) return null;
    final displayName = parts.first.trim();
    final bubbleId = parts.sublist(1).join('|').trim();
    if (displayName.isEmpty || bubbleId.isEmpty) return null;
    return _EndpointInfo(displayName: displayName, bubbleId: bubbleId);
  }
}

class _EndpointInfo {
  final String displayName;
  final String bubbleId;
  const _EndpointInfo({required this.displayName, required this.bubbleId});
}