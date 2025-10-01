import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

import '../../models/bubble_event.dart';
import '../../models/bubble_settings.dart';
import '../../models/chat_message.dart';
import '../../models/peer_profile.dart';
import '../echo_comms.dart';
import '../log.dart';
import '../platform_info.dart';
import '../security/crypto_utils.dart';
import 'lan_beacon.dart';
import 'lan_socket.dart';

class LanCommsService implements EchoComms {
  static const int defaultPort = 4040;

  final int hostPort;
  LanSocketServer? _server;
  LanSocketClient? _client;

  String? _displayName;
  String? _bubbleId;

  BubbleSettings _bubbleSettings = BubbleSettings.public();

  SecretKey? _sessionKey;

  String? _myPhone;
  String? _myHandle;
  String? _myProfileImageB64;

  String? _lanHost;
  int _lanPort = defaultPort;

  bool _running = false;

  final String _nodeId = const Uuid().v4();

  final LanBeacon _beacon = LanBeacon();

  StreamSubscription? _serverSub;
  StreamSubscription? _clientSub;

  @override
  bool get isRunning => _running;

  final _peersById = <String, PeerProfile>{};
  final _peersController = StreamController<List<PeerProfile>>.broadcast();
  final _messagesController = StreamController<ChatMessage>.broadcast();
  final _eventsController = StreamController<BubbleEvent>.broadcast();

  @override
  Stream<List<PeerProfile>> get peersStream => _peersController.stream;

  @override
  Stream<ChatMessage> get messagesStream => _messagesController.stream;

  @override
  Stream<BubbleEvent> get eventsStream => _eventsController.stream;

  final Map<String, DateTime> _seenMessageIds = {};
  final Map<String, DateTime> _seenEventIds = {};
  Timer? _seenPrune;

  Uint8List? _hostSalt; // 16 bytes
  Uint8List? _hostNonce; // 16 bytes
  Uint8List? _clientNonce; // 16 bytes

  LanCommsService({this.hostPort = defaultPort});

  @override
  void setMyContactInfo({String? phone, String? handle, String? profileImageB64}) {
    _myPhone = phone?.trim();
    _myHandle = handle?.trim();
    final v = profileImageB64?.trim();
    _myProfileImageB64 = (v == null || v.isEmpty) ? null : v;

    if (_running) {
      _sendProfile(toServer: true);
    }
  }

  @override
  Future<void> setLanHost(String host, {int port = defaultPort}) async {
    _lanHost = host.trim().isEmpty ? null : host.trim();
    _lanPort = port;

    if (_running) {
      await stop();
      final dn = _displayName;
      final bid = _bubbleId;
      final bs = _bubbleSettings;
      if (dn != null && bid != null) {
        await start(displayName: dn, bubbleId: bid, bubbleSettings: bs);
      }
    }
  }

  @override
  Future<void> start({
    required String displayName,
    required String bubbleId,
    BubbleSettings? bubbleSettings,
  }) async {
    _displayName = displayName;
    _bubbleId = bubbleId;
    _bubbleSettings = bubbleSettings ?? BubbleSettings.public();

    _sessionKey = null;
    _hostSalt = null;
    _hostNonce = null;
    _clientNonce = null;

    if (_running) await stop();
    _running = true;

    _peersById.clear();
    _emitPeers();

    _seenPrune ??= Timer.periodic(const Duration(seconds: 15), (_) => _pruneSeen());

    if (_lanHost != null) {
      await _startClientMode(host: _lanHost!, port: _lanPort);
    } else {
      await _startHostMode();
    }

    logInfo(
      'LAN started (host=${_lanHost ?? "self"} port=${_lanHost == null ? hostPort : _lanPort} '
          'private=${_bubbleSettings.isPrivate} requirePw=${_bubbleSettings.requirePassword})',
    );
  }

  Future<void> _startHostMode() async {
    _server = LanSocketServer(port: hostPort);
    try {
      await _server!.start();
    } catch (e) {
      logInfo('LAN host mode not available: $e');
      _server = null;
    }

    _client = LanSocketClient();
    await _client!.connect(host: '127.0.0.1', port: hostPort);

    _serverSub = _server?.incoming.listen((inc) async {
      await _handleServerIncoming(peerId: inc.peerId, text: inc.text);
    });

    _clientSub = _client!.incoming.listen((text) async {
      await _handleClientIncoming(text);
    });

    if (_bubbleSettings.isPrivate) {
      _hostSalt = CryptoUtils.randomBytes(16);
      _hostNonce = CryptoUtils.randomBytes(16);
    }

    await _sendProfile(toServer: true);

    if (!isWeb && _server != null) {
      final dn = _displayName;
      final bid = _bubbleId;
      if (dn != null && bid != null) {
        await _beacon.startBroadcaster(
          bubbleId: bid,
          displayName: dn,
          peerId: _nodeId,
          wsPort: hostPort,
        );
        logInfo('LAN beacon broadcasting started (udp ${LanBeacon.defaultBeaconPort})');
      }
    }
  }

  Future<void> _startClientMode({required String host, required int port}) async {
    _client = LanSocketClient();
    await _client!.connect(host: host, port: port);

    _clientSub = _client!.incoming.listen((text) async {
      await _handleClientIncoming(text);
    });

    if (_bubbleSettings.isPrivate) {
      await _sendJoinHello();
    } else {
      await _sendProfile(toServer: true);
    }
  }

  // -------------------------
  // Join handshake
  // -------------------------

  Future<void> _sendJoinHello() async {
    final bid = _bubbleId;
    if (bid == null) return;

    _clientNonce = CryptoUtils.randomBytes(16);

    final msg = jsonEncode({
      'type': 'join_hello',
      'bubbleId': bid,
      'invite': _bubbleSettings.inviteCode,
      'clientNonce': CryptoUtils.b64(_clientNonce!),
    });

    await _client?.send(msg);
  }

  Future<void> _handleJoinChallenge(Map<String, dynamic> map) async {
    final bid = _bubbleId;
    if (bid == null) return;

    final saltB64 = (map['salt'] as String?)?.trim();
    final hostNonceB64 = (map['hostNonce'] as String?)?.trim();
    final requirePw = map['requirePw'] == true;

    if (saltB64 == null || hostNonceB64 == null) {
      logInfo('join_challenge missing fields');
      return;
    }

    final salt = CryptoUtils.b64d(saltB64);
    final hostNonce = CryptoUtils.b64d(hostNonceB64);
    final clientNonce = _clientNonce;
    if (clientNonce == null) return;

    final password = _bubbleSettings.password ?? '';
    if (requirePw && password.trim().isEmpty) {
      logInfo('join_challenge: password required but missing');
      await _client?.send(jsonEncode({
        'type': 'join_fail',
        'bubbleId': bid,
        'reason': 'password_required',
      }));
      return;
    }

    final pwKey = await CryptoUtils.derivePasswordKey(
      password: password,
      salt: salt,
    );

    final proof = await CryptoUtils.makeJoinProof(
      passwordKey: pwKey,
      bubbleId: bid,
      clientNonce: clientNonce,
      hostNonce: hostNonce,
    );

    final msg = jsonEncode({
      'type': 'join_proof',
      'bubbleId': bid,
      'invite': _bubbleSettings.inviteCode,
      'clientNonce': CryptoUtils.b64(clientNonce),
      'proof': CryptoUtils.b64(proof),
    });

    await _client?.send(msg);
  }

  Future<void> _handleJoinOk(Map<String, dynamic> map) async {
    final bid = _bubbleId;
    if (bid == null) return;

    final sessionSaltB64 = (map['sessionSalt'] as String?)?.trim();
    final hostNonceB64 = (map['hostNonce'] as String?)?.trim();
    final clientNonce = _clientNonce;

    if (sessionSaltB64 == null || hostNonceB64 == null || clientNonce == null) {
      await _sendProfile(toServer: true);
      return;
    }

    final sessionSalt = CryptoUtils.b64d(sessionSaltB64);
    final hostNonce = CryptoUtils.b64d(hostNonceB64);

    final ikm = BytesBuilder()..add(clientNonce)..add(hostNonce);

    if (_bubbleSettings.isPrivate && _bubbleSettings.requirePassword) {
      final pw = _bubbleSettings.password ?? '';
      final pwSaltB64 = (map['pwSalt'] as String?)?.trim();
      final saltForPw = pwSaltB64 != null && pwSaltB64.isNotEmpty
          ? CryptoUtils.b64d(pwSaltB64)
          : sessionSalt;
      final pwKey = await CryptoUtils.derivePasswordKey(password: pw, salt: saltForPw);
      final pwKeyBytes = await pwKey.extractBytes();
      ikm.add(pwKeyBytes);
    }

    _sessionKey = await CryptoUtils.hkdf(
      ikm: ikm.toBytes(),
      salt: sessionSalt,
      info: 'echo/lan/session/$bid',
      bits: 256,
    );

    await _sendProfile(toServer: true);
  }

  // -------------------------
  // Profile
  // -------------------------

  Future<void> _sendProfile({required bool toServer}) async {
    final dn = _displayName;
    final bid = _bubbleId;
    if (dn == null || bid == null) return;

    final msg = jsonEncode({
      'type': 'profile',
      'displayName': dn,
      'bubbleId': bid,
      'phone': _myPhone,
      'handle': _myHandle,
      'profileImageB64': _myProfileImageB64,
    });

    if (toServer) {
      await _client?.send(msg);
    }
  }

  // -------------------------
  // Incoming: server relay
  // -------------------------

  Future<void> _handleServerIncoming({required String peerId, required String text}) async {
    final map = _tryDecode(text);
    if (map == null) return;

    final type = (map['type'] as String?)?.trim();

    if (type == '_disconnect') {
      _peersById.remove(peerId);
      _emitPeers();
      _server?.broadcast(
        jsonEncode({'type': 'peer_gone', 'peerId': peerId}),
        exceptPeerId: peerId,
      );
      return;
    }

    if (type == '_connect') return;

    if (type == 'join_hello') {
      await _handleServerJoinHello(peerId, map);
      return;
    }
    if (type == 'join_proof') {
      await _handleServerJoinProof(peerId, map);
      return;
    }
    if (type == 'join_fail') return;

    if (type == 'profile') {
      final bubbleId = (map['bubbleId'] as String?)?.trim();
      if (bubbleId == null || bubbleId.isEmpty) return;

      final out = Map<String, dynamic>.from(map)..['peerId'] = peerId;

      _upsertPeerFromProfile(out);

      _server?.broadcast(jsonEncode(out), exceptPeerId: peerId);

      for (final p in _peersById.values) {
        final rosterMsg = jsonEncode({
          'type': 'profile',
          'peerId': p.endpointId,
          'displayName': p.displayName,
          'bubbleId': p.bubbleId,
          'phone': p.phone,
          'handle': p.handle,
          'profileImageB64': p.profileImageB64,
        });
        _server?.send(peerId, rosterMsg);
      }
      return;
    }

    if (type == 'chat') {
      final bubbleId = (map['bubbleId'] as String?)?.trim();
      if (bubbleId == null || bubbleId.isEmpty) return;

      final out = Map<String, dynamic>.from(map)..['fromPeerId'] = peerId;

      final toPeerId = (out['toPeerId'] as String?)?.trim();
      if (toPeerId == null || toPeerId.isEmpty || toPeerId == '*') {
        _server?.broadcast(jsonEncode(out), exceptPeerId: peerId);
      } else {
        _server?.send(toPeerId, jsonEncode(out));
      }

      await _emitChatFromMap(out, peerIdFallback: peerId, transport: 'wifi');
      return;
    }

    if (type == 'event') {
      final bubbleId = (map['bubbleId'] as String?)?.trim();
      if (bubbleId == null || bubbleId.isEmpty) return;

      final out = Map<String, dynamic>.from(map)..['fromPeerId'] = peerId;

      final toPeerId = (out['toPeerId'] as String?)?.trim();
      if (toPeerId == null || toPeerId.isEmpty || toPeerId == '*') {
        _server?.broadcast(jsonEncode(out), exceptPeerId: peerId);
      } else {
        _server?.send(toPeerId, jsonEncode(out));
      }

      _emitEventFromMap(out, peerIdFallback: peerId, transport: 'wifi');
      return;
    }
  }

  Future<void> _handleServerJoinHello(String peerId, Map<String, dynamic> map) async {
    final bid = _bubbleId;
    if (bid == null) return;

    if (!_bubbleSettings.isPrivate) {
      final sessionSalt = CryptoUtils.randomBytes(16);
      final hostNonce = _hostNonce ??= CryptoUtils.randomBytes(16);
      _server?.send(
        peerId,
        jsonEncode({
          'type': 'join_ok',
          'bubbleId': bid,
          'sessionSalt': CryptoUtils.b64(sessionSalt),
          'hostNonce': CryptoUtils.b64(hostNonce),
        }),
      );
      return;
    }

    final invite = (map['invite'] as String?)?.trim();
    if (invite == null || invite.isEmpty || invite != _bubbleSettings.inviteCode) {
      _server?.send(peerId, jsonEncode({'type': 'join_denied', 'bubbleId': bid, 'reason': 'bad_invite'}));
      return;
    }

    final salt = _hostSalt ??= CryptoUtils.randomBytes(16);
    final hostNonce = _hostNonce ??= CryptoUtils.randomBytes(16);

    _server?.send(
      peerId,
      jsonEncode({
        'type': 'join_challenge',
        'bubbleId': bid,
        'salt': CryptoUtils.b64(salt),
        'hostNonce': CryptoUtils.b64(hostNonce),
        'requirePw': _bubbleSettings.requirePassword,
      }),
    );
  }

  Future<void> _handleServerJoinProof(String peerId, Map<String, dynamic> map) async {
    final bid = _bubbleId;
    if (bid == null) return;

    if (!_bubbleSettings.isPrivate) {
      final sessionSalt = CryptoUtils.randomBytes(16);
      final hostNonce = _hostNonce ??= CryptoUtils.randomBytes(16);
      _server?.send(
        peerId,
        jsonEncode({
          'type': 'join_ok',
          'bubbleId': bid,
          'sessionSalt': CryptoUtils.b64(sessionSalt),
          'hostNonce': CryptoUtils.b64(hostNonce),
        }),
      );
      return;
    }

    final invite = (map['invite'] as String?)?.trim();
    if (invite == null || invite.isEmpty || invite != _bubbleSettings.inviteCode) {
      _server?.send(peerId, jsonEncode({'type': 'join_denied', 'bubbleId': bid, 'reason': 'bad_invite'}));
      return;
    }

    final salt = _hostSalt ??= CryptoUtils.randomBytes(16);
    final hostNonce = _hostNonce ??= CryptoUtils.randomBytes(16);

    final clientNonceB64 = (map['clientNonce'] as String?)?.trim();
    final proofB64 = (map['proof'] as String?)?.trim();
    if (clientNonceB64 == null || proofB64 == null) {
      _server?.send(peerId, jsonEncode({'type': 'join_denied', 'bubbleId': bid, 'reason': 'malformed'}));
      return;
    }

    final clientNonce = CryptoUtils.b64d(clientNonceB64);
    final provided = CryptoUtils.b64d(proofB64);

    if (!_bubbleSettings.requirePassword) {
      final sessionSalt = CryptoUtils.randomBytes(16);
      _server?.send(
        peerId,
        jsonEncode({
          'type': 'join_ok',
          'bubbleId': bid,
          'sessionSalt': CryptoUtils.b64(sessionSalt),
          'hostNonce': CryptoUtils.b64(hostNonce),
        }),
      );
      return;
    }

    final password = _bubbleSettings.password ?? '';
    if (password.trim().isEmpty) {
      _server?.send(peerId, jsonEncode({'type': 'join_denied', 'bubbleId': bid, 'reason': 'host_no_password'}));
      return;
    }

    final pwKey = await CryptoUtils.derivePasswordKey(password: password, salt: salt);
    final expected = await CryptoUtils.makeJoinProof(
      passwordKey: pwKey,
      bubbleId: bid,
      clientNonce: clientNonce,
      hostNonce: hostNonce,
    );

    if (!CryptoUtils.constantTimeEquals(expected, provided)) {
      _server?.send(peerId, jsonEncode({'type': 'join_denied', 'bubbleId': bid, 'reason': 'bad_password'}));
      return;
    }

    final sessionSalt = CryptoUtils.randomBytes(16);
    _server?.send(
      peerId,
      jsonEncode({
        'type': 'join_ok',
        'bubbleId': bid,
        'sessionSalt': CryptoUtils.b64(sessionSalt),
        'hostNonce': CryptoUtils.b64(hostNonce),
        'pwSalt': CryptoUtils.b64(salt),
      }),
    );
  }

  // -------------------------
  // Incoming: client-side
  // -------------------------

  Future<void> _handleClientIncoming(String text) async {
    final map = _tryDecode(text);
    if (map == null) return;

    final type = (map['type'] as String?)?.trim();

    if (type == '_connect') {
      if (_bubbleSettings.isPrivate) {
        await _sendJoinHello();
      } else {
        await _sendProfile(toServer: true);
      }
      return;
    }

    if (type == 'join_challenge') {
      await _handleJoinChallenge(map);
      return;
    }
    if (type == 'join_ok') {
      await _handleJoinOk(map);
      return;
    }
    if (type == 'join_denied') {
      final reason = (map['reason'] as String?) ?? 'denied';
      _showJoinDenied(reason);
      return;
    }

    if (type == 'peer_gone') {
      final pid = (map['peerId'] as String?)?.trim();
      if (pid != null) {
        _peersById.remove(pid);
        _emitPeers();
      }
      return;
    }

    if (type == 'profile') {
      _upsertPeerFromProfile(map);
      return;
    }

    if (type == 'chat') {
      await _emitChatFromMap(
        map,
        peerIdFallback: (map['fromPeerId'] as String?)?.trim(),
        transport: 'wifi',
      );
      return;
    }

    if (type == 'event') {
      _emitEventFromMap(
        map,
        peerIdFallback: (map['fromPeerId'] as String?)?.trim(),
        transport: 'wifi',
      );
      return;
    }
  }

  void _showJoinDenied(String reason) {
    logInfo('Join denied: $reason');
    stop();
  }

  // -------------------------
  // Peer roster
  // -------------------------

  void _upsertPeerFromProfile(Map<String, dynamic> map) {
    final pid = (map['peerId'] as String?)?.trim();
    final name = (map['displayName'] as String?)?.trim();
    final bubbleId = (map['bubbleId'] as String?)?.trim();

    if (pid == null || pid.isEmpty || name == null || name.isEmpty || bubbleId == null || bubbleId.isEmpty) {
      return;
    }
    if (bubbleId != _bubbleId) return;

    final phone = (map['phone'] as String?)?.trim();
    final handle = (map['handle'] as String?)?.trim();
    final img = (map['profileImageB64'] as String?)?.trim();

    _peersById[pid] = PeerProfile(
      endpointId: pid,
      displayName: name,
      bubbleId: bubbleId,
      firstSeen: _peersById[pid]?.firstSeen ?? DateTime.now(),
      phone: (phone == null || phone.isEmpty) ? null : phone,
      handle: (handle == null || handle.isEmpty) ? null : handle,
      profileImageB64: (img == null || img.isEmpty) ? null : img,
    );

    _emitPeers();
  }

  // -------------------------
  // Chat / Event emit
  // -------------------------

  Future<void> _emitChatFromMap(
      Map<String, dynamic> map, {
        required String? peerIdFallback,
        required String transport,
      }) async {
    final bubbleId = (map['bubbleId'] as String?)?.trim();
    if (bubbleId != _bubbleId) return;

    final fromPeerId = (map['fromPeerId'] as String?)?.trim() ?? peerIdFallback;
    if (fromPeerId == null || fromPeerId.isEmpty) return;

    final toPeerId = (map['toPeerId'] as String?)?.trim() ?? '*';

    final msgId = (map['msgId'] as String?)?.trim();
    if (msgId != null && msgId.isNotEmpty) {
      if (_seenMessageIds.containsKey(msgId)) return;
      _seenMessageIds[msgId] = DateTime.now();
    }

    String text = (map['text'] as String?) ?? '';
    if (map['enc'] == true) {
      final sk = _sessionKey;
      final payloadB64 = (map['payload'] as String?)?.trim();
      if (sk != null && payloadB64 != null && payloadB64.isNotEmpty) {
        try {
          text = await awaitCryptoDecryptText(payloadB64, sk, aad: 'echo/chat/$bubbleId');
        } catch (_) {
          text = '🔒 Encrypted message (could not decrypt)';
        }
      } else {
        text = '🔒 Encrypted message';
      }
    }

    final fromName = (map['from'] as String?)?.trim();

    _messagesController.add(ChatMessage(
      peerId: fromPeerId,
      fromMe: false,
      text: text,
      at: DateTime.tryParse((map['ts'] as String?) ?? '') ?? DateTime.now(),
      messageId: msgId ?? '',
      bubbleId: bubbleId ?? '',
      fromPeerId: fromPeerId,
      toPeerId: toPeerId,
      fromName: fromName,
      transport: transport,
    ));
  }

  void _emitEventFromMap(
      Map<String, dynamic> map, {
        required String? peerIdFallback,
        required String transport,
      }) {
    final bubbleId = (map['bubbleId'] as String?)?.trim();
    if (bubbleId != _bubbleId) return;

    final fromPeerId = (map['fromPeerId'] as String?)?.trim() ?? peerIdFallback;
    if (fromPeerId == null || fromPeerId.isEmpty) return;

    final eventId = (map['eventId'] as String?)?.trim();
    if (eventId != null && eventId.isNotEmpty) {
      if (_seenEventIds.containsKey(eventId)) return;
      _seenEventIds[eventId] = DateTime.now();
    }

    final evt = BubbleEvent.tryFromJson(
      Map<String, dynamic>.from(map)
        ..['fromPeerId'] = fromPeerId
        ..['transport'] = transport,
    );
    if (evt == null) return;

    _eventsController.add(evt);
  }

  Map<String, dynamic>? _tryDecode(String text) {
    try {
      final v = jsonDecode(text);
      if (v is Map<String, dynamic>) return v;
      return null;
    } catch (_) {
      return null;
    }
  }

  void _emitPeers() {
    final list = _peersById.values.toList()
      ..sort((a, b) => a.firstSeen.compareTo(b.firstSeen));
    _peersController.add(list);
  }

  void _pruneSeen() {
    final now = DateTime.now();
    _seenMessageIds.removeWhere((_, t) => now.difference(t) > const Duration(minutes: 5));
    _seenEventIds.removeWhere((_, t) => now.difference(t) > const Duration(minutes: 5));
  }

  // -------------------------
  // Outgoing
  // -------------------------

  @override
  Future<void> sendMessage(String peerId, String text) async {
    final dn = _displayName;
    final bid = _bubbleId;
    if (dn == null || bid == null) return;

    final msgId = const Uuid().v4();
    final ts = DateTime.now();

    final sk = _sessionKey;
    Map<String, dynamic> packet;
    if (sk != null) {
      final payloadB64 = await awaitCryptoEncryptText(text, sk, aad: 'echo/chat/$bid');
      packet = {
        'type': 'chat',
        'msgId': msgId,
        'toPeerId': peerId,
        'from': dn,
        'bubbleId': bid,
        'ts': ts.toIso8601String(),
        'enc': true,
        'payload': payloadB64,
      };
    } else {
      packet = {
        'type': 'chat',
        'msgId': msgId,
        'toPeerId': peerId,
        'text': text,
        'from': dn,
        'bubbleId': bid,
        'ts': ts.toIso8601String(),
      };
    }

    final jsonPacket = jsonEncode(packet);

    _seenMessageIds[msgId] = DateTime.now();
    await _client?.send(jsonPacket);

    _messagesController.add(ChatMessage(
      peerId: peerId,
      fromMe: true,
      text: text,
      at: ts,
      messageId: msgId,
      bubbleId: bid,
      fromPeerId: 'me',
      toPeerId: peerId,
      fromName: dn,
      transport: 'wifi',
    ));
  }

  @override
  Future<void> sendEvent(BubbleEvent event, {String toPeerId = '*'}) async {
    final bid = _bubbleId;
    if (bid == null) return;
    if (event.bubbleId != bid) return;

    final packetMap = Map<String, dynamic>.from(event.toJson())
      ..['toPeerId'] = toPeerId
      ..['transport'] = 'wifi';

    final json = jsonEncode(packetMap);

    _seenEventIds[event.eventId] = DateTime.now();
    await _client?.send(json);

    final echoed = BubbleEvent.tryFromJson(Map<String, dynamic>.from(packetMap));
    if (echoed != null) {
      _eventsController.add(echoed);
    }
  }

  @override
  Future<void> stop() async {
    _running = false;

    _sessionKey = null;
    _hostSalt = null;
    _hostNonce = null;
    _clientNonce = null;

    _seenPrune?.cancel();
    _seenPrune = null;
    _seenMessageIds.clear();
    _seenEventIds.clear();

    await _serverSub?.cancel();
    _serverSub = null;

    await _clientSub?.cancel();
    _clientSub = null;

    await _client?.dispose();
    _client = null;

    await _server?.dispose();
    _server = null;

    await _beacon.stopBroadcaster();

    _peersById.clear();
    _emitPeers();

    logInfo('LAN stopped');
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _beacon.dispose();
    await _peersController.close();
    await _messagesController.close();
    await _eventsController.close();
  }
}

/// ---------------------------------------------------------------------------
/// Small helpers to avoid making CryptoUtils depend on app models.
/// ---------------------------------------------------------------------------

Future<String> awaitCryptoEncryptText(String text, SecretKey key, {required String aad}) async {
  final payload = await CryptoUtils.encryptJson(
    json: {'t': text},
    key: key,
    aad: aad,
  );
  return CryptoUtils.b64(payload);
}

Future<String> awaitCryptoDecryptText(String payloadB64, SecretKey key, {required String aad}) async {
  final payload = CryptoUtils.b64d(payloadB64);
  final map = await CryptoUtils.decryptJson(payload: payload, key: key, aad: aad);
  final t = map['t'];
  if (t is String) return t;
  return '';
}