import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/bubble_settings.dart';
import '../models/chat_message.dart';
import '../models/kept_contact.dart';
import '../models/peer_profile.dart';
import '../services/bubble_service.dart';
import '../services/bubble_session_controller.dart';
import '../services/bubbles/bubble_discovery_service.dart';
import '../services/contacts_repo.dart';
import '../services/echo_comms.dart';
import '../services/lan/lan_comms_service.dart';
import '../services/lan/lan_discovery.dart';
import '../services/platform_info.dart';
import '../services/permissions_service.dart';
import 'bubble_page.dart';
import 'chat_page.dart';
import 'kept_page.dart';
import 'guide_page.dart';
import '../services/nearby_optional.dart';
import '../services/lan/android_multicast_lock.dart';

enum _PeerSortMode { firstSeen, name }
enum _Transport { wifi, nearby }

class _PeerEntry {
  final _Transport transport;
  final PeerProfile peer;
  const _PeerEntry({required this.transport, required this.peer});
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  static const _kDisplayNameKey = 'display_name_v1';
  static const _kDeviceIdKey = 'device_id_v1';
  static const _kProfileImageB64Key = 'profile_image_b64_v1';
  static const _kPhoneKey = 'my_phone_v1';
  static const _kHandleKey = 'my_handle_v1';
  static const _kEventPeerIdKey = 'event_peer_id_v1';
  static const _kLanHostKey = 'lan_host';
  static const _kLanPortKey = 'lan_port';
  static const _kHostPrivateKey = 'host_private_v1';
  static const _kHostInviteKey = 'host_invite_v1';
  static const _kHostRequirePwKey = 'host_require_pw_v1';
  static const _kHostPasswordKey = 'host_password_v1';
  static const Color _brandGreen = Color(0xFF0F9D58);
  static const Color _liveRed = Color(0xFFE53935);
  static const Color _softField = Color(0xFFF7F8F7);

  static const double _radiusM = 35;

  final _bubbleService = BubbleService(radiusM: _radiusM);

  // Two transports:
  late final EchoComms _wifiComms; // LAN WebSocket
  EchoComms? _nearbyComms; // Android Nearby (optional)

  // Bubble discovery (LAN/NSD)
  final BubbleDiscoveryService _bubbleDiscovery =
  BubbleDiscoveryService(serviceType: '_echo._tcp');
  StreamSubscription<List<DiscoveredBubble>>? _bubblesSub;
  List<DiscoveredBubble> _bubbles = const [];
  String? _joinedBubbleId; // bubble you joined via discovery

  // UDP beacon discovery (makes Windows-hosted bubbles visible)
  final LanDiscovery _lanDiscovery = LanDiscovery();
  StreamSubscription<List<LanBubbleAnnouncement>>? _lanSub;
  List<LanBubbleAnnouncement> _lanBubbles = const [];

  // Session-scoped ephemeral features controller (polls/canvas/shout/etc.)
  BubbleSessionController? _bubbleSession;

  final _repo = ContactsRepo();

  final _displayNameCtrl = TextEditingController();
  final _peerSearchCtrl = TextEditingController();

  final _imagePicker = ImagePicker();

  StreamSubscription<List<PeerProfile>>? _wifiPeersSub;
  StreamSubscription<ChatMessage>? _wifiMsgSub;

  StreamSubscription<List<PeerProfile>>? _nearbyPeersSub;
  StreamSubscription<ChatMessage>? _nearbyMsgSub;

  List<PeerProfile> _wifiPeers = const [];
  List<PeerProfile> _nearbyPeers = const [];
  List<KeptContact> _kept = const [];

  // Separate unread + last message by transport
  final Map<String, int> _unreadByKey = {}; // key = "wifi:peerId" or "nearby:peerId"
  final Map<String, ChatMessage> _lastMsgByKey = {};

  // In-memory chat history for the current bubble session (self-destruct on leave)
  final Map<String, List<ChatMessage>> _historyByKey = {};

  bool _permissionsOk = false;
  bool _busy = false;

  double? _distanceFromCenter;
  Position? _latestPos;

  _PeerSortMode _sortMode = _PeerSortMode.firstSeen;
  bool _showDebug = false;

  Uint8List? _profileBytes;
  String? _myPhone;
  String? _myHandle;

  // LAN (Web/Desktop): connect to a host running Echo LAN server
  final TextEditingController _lanHostCtrl = TextEditingController();
  int _lanPort = 4040;
  final TextEditingController _lanPortCtrl =
  TextEditingController(text: '4040');

  // ✅ Host privacy UI state (persisted)
  bool _hostPrivate = false;
  bool _hostRequirePassword = false;
  final TextEditingController _hostInviteCtrl = TextEditingController();
  final TextEditingController _hostPasswordCtrl = TextEditingController();

  late final AnimationController _livePulseCtrl; // LIVE pill pulse + dot
  late final AnimationController _ctaBreathCtrl; // subtle CTA breath when LIVE
  late final AnimationController _pressCtrl; // press scale

  @override
  void initState() {
    super.initState();

    _wifiComms = LanCommsService();
    _nearbyComms = createNearbyOptionalComms();

    _livePulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _ctaBreathCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 110),
      lowerBound: 0,
      upperBound: 1,
    );

    _init();
  }

  String _k(_Transport t, String peerId) => '${t.name}:$peerId';

  void _clearSessionState() {
    _unreadByKey.clear();
    _lastMsgByKey.clear();
    _historyByKey.clear();
  }

  ImageProvider? _peerAvatarProvider(PeerProfile p) {
    final b64 = p.profileImageB64;
    if (b64 == null || b64.trim().isEmpty) return null;
    try {
      return MemoryImage(base64Decode(b64.trim()));
    } catch (_) {
      return null;
    }
  }

  String _genInviteCode() {
    final raw = const Uuid().v4().replaceAll('-', '').toUpperCase();
    return raw.substring(0, 8);
  }

  Future<void> _loadHostPrefs(SharedPreferences prefs) async {
    _hostPrivate = prefs.getBool(_kHostPrivateKey) ?? false;
    _hostRequirePassword = prefs.getBool(_kHostRequirePwKey) ?? false;

    final invite = (prefs.getString(_kHostInviteKey) ?? '').trim();
    final pw = (prefs.getString(_kHostPasswordKey) ?? '').trim();

    _hostInviteCtrl.text = invite.isEmpty ? _genInviteCode() : invite;
    _hostPasswordCtrl.text = pw;
  }

  Future<void> _saveHostPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHostPrivateKey, _hostPrivate);
    await prefs.setBool(
        _kHostRequirePwKey, _hostPrivate ? _hostRequirePassword : false);

    final invite = _hostInviteCtrl.text.trim();
    if (_hostPrivate && invite.isNotEmpty) {
      await prefs.setString(_kHostInviteKey, invite);
    } else {
      await prefs.remove(_kHostInviteKey);
    }

    final pw = _hostPasswordCtrl.text.trim();
    if (_hostPrivate && _hostRequirePassword && pw.isNotEmpty) {
      await prefs.setString(_kHostPasswordKey, pw);
    } else {
      await prefs.remove(_kHostPasswordKey);
    }
  }

  BubbleSettings _currentHostSettings() {
    if (!_hostPrivate) return BubbleSettings.public();
    return BubbleSettings(
      isPrivate: true,
      requirePassword: _hostRequirePassword,
      inviteCode: _hostInviteCtrl.text.trim(),
      password: _hostRequirePassword ? _hostPasswordCtrl.text : null,
    );
  }

  Future<BubbleSettings?> _promptHostBubbleSettings() async {
    if (_hostInviteCtrl.text.trim().isEmpty) {
      _hostInviteCtrl.text = _genInviteCode();
    }

    final res = await showDialog<BubbleSettings>(
      context: context,
      builder: (ctx) {
        bool private = _hostPrivate;
        bool requirePw = _hostRequirePassword;

        final inviteCtrl =
        TextEditingController(text: _hostInviteCtrl.text.trim());
        final pwCtrl = TextEditingController(text: _hostPasswordCtrl.text);

        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              backgroundColor: Colors.white,
              title: const Text('Host bubble privacy'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Private bubble'),
                    subtitle: const Text('Invite-only'),
                    value: private,
                    onChanged: (v) {
                      setLocal(() => private = v);
                      if (v && inviteCtrl.text.trim().isEmpty) {
                        inviteCtrl.text = _genInviteCode();
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  if (private) ...[
                    TextField(
                      controller: inviteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Invite code',
                        hintText: 'e.g. 8 characters',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Require password'),
                      subtitle: const Text('Recommended'),
                      value: requirePw,
                      onChanged: (v) => setLocal(() => requirePw = v),
                    ),
                    if (requirePw) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: pwCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Private (no password) = invite-only.\nPrivate + password = invite + password.',
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.60),
                      fontSize: 12,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brandGreen,
                    foregroundColor: Colors.white,
                    elevation: 0,
                  ),
                  onPressed: () {
                    if (private) {
                      if (inviteCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Invite code cannot be empty.')),
                        );
                        return;
                      }
                      if (requirePw && pwCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Password cannot be empty.')),
                        );
                        return;
                      }
                    }

                    // Commit to state
                    _hostPrivate = private;
                    _hostRequirePassword = private ? requirePw : false;

                    _hostInviteCtrl.text =
                    inviteCtrl.text.trim().isEmpty ? _genInviteCode() : inviteCtrl.text.trim();
                    _hostPasswordCtrl.text = pwCtrl.text;

                    final settings = private
                        ? BubbleSettings(
                      isPrivate: true,
                      requirePassword: _hostRequirePassword,
                      inviteCode: _hostInviteCtrl.text.trim(),
                      password: _hostRequirePassword
                          ? _hostPasswordCtrl.text
                          : null,
                    )
                        : BubbleSettings.public();

                    Navigator.of(ctx).pop(settings);
                  },
                  child: const Text('Continue'),
                ),
              ],
            );
          },
        );
      },
    );

    if (res != null) {
      await _saveHostPrefs();
      if (mounted) setState(() {});
    }
    return res;
  }

  Future<BubbleSettings?> _promptJoinCredentials({
    required String bubbleName,
  }) async {
    final inviteCtrl = TextEditingController(text: '');
    final pwCtrl = TextEditingController(text: '');

    final res = await showDialog<BubbleSettings>(
      context: context,
      builder: (ctx) {
        bool isPrivate = false;
        bool requirePw = false;

        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              backgroundColor: Colors.white,
              title: Text('Join $bubbleName'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('This is a private bubble'),
                    subtitle: const Text('Turn on if host gave you an invite code'),
                    value: isPrivate,
                    onChanged: (v) => setLocal(() => isPrivate = v),
                  ),
                  if (isPrivate) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: inviteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Invite code',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Password required'),
                      subtitle:
                      const Text('Turn on if host set a password'),
                      value: requirePw,
                      onChanged: (v) => setLocal(() => requirePw = v),
                    ),
                    if (requirePw) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: pwCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'If it’s public, leave these off and join normally.',
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.60),
                      fontSize: 12,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brandGreen,
                    foregroundColor: Colors.white,
                    elevation: 0,
                  ),
                  onPressed: () {
                    if (isPrivate) {
                      if (inviteCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Enter an invite code.')),
                        );
                        return;
                      }
                      if (requirePw && pwCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Enter the password.')),
                        );
                        return;
                      }
                    }

                    final settings = isPrivate
                        ? BubbleSettings(
                      isPrivate: true,
                      requirePassword: requirePw,
                      inviteCode: inviteCtrl.text.trim(),
                      password: requirePw ? pwCtrl.text : null,
                    )
                        : BubbleSettings.public();

                    Navigator.of(ctx).pop(settings);
                  },
                  child: const Text('Join'),
                ),
              ],
            );
          },
        );
      },
    );

    return res;
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();

    final name = prefs.getString(_kDisplayNameKey) ?? '';
    _displayNameCtrl.text = name;

    prefs.getString(_kDeviceIdKey) ??
        await prefs.setString(_kDeviceIdKey, const Uuid().v4());

    prefs.getString(_kEventPeerIdKey) ??
        await prefs.setString(_kEventPeerIdKey, const Uuid().v4());

    await _loadHostPrefs(prefs);

    final imgB64 = prefs.getString(_kProfileImageB64Key);
    if (imgB64 != null && imgB64.isNotEmpty) {
      try {
        _profileBytes = base64Decode(imgB64);
      } catch (_) {}
    }

    final kept = await _repo.load();

    final rawPhone = prefs.getString(_kPhoneKey);
    final rawHandle = prefs.getString(_kHandleKey);
    _myPhone =
    (rawPhone == null || rawPhone.trim().isEmpty) ? null : rawPhone.trim();
    _myHandle = (rawHandle == null || rawHandle.trim().isEmpty)
        ? null
        : rawHandle.trim();

    final rawImgB64 = prefs.getString(_kProfileImageB64Key);
    final profileImageB64 =
    (rawImgB64 == null || rawImgB64.trim().isEmpty) ? null : rawImgB64.trim();

    _wifiComms.setMyContactInfo(
      phone: _myPhone,
      handle: _myHandle,
      profileImageB64: profileImageB64,
    );
    _nearbyComms?.setMyContactInfo(
      phone: _myPhone,
      handle: _myHandle,
      profileImageB64: profileImageB64,
    );

    if (isWeb || isDesktop) {
      final savedHost = prefs.getString(_kLanHostKey) ?? '';
      final savedPort = prefs.getInt(_kLanPortKey) ?? 4040;
      _lanHostCtrl.text = savedHost;
      _lanPort = savedPort;
      _lanPortCtrl.text = savedPort.toString();

      try {
        await _wifiComms.setLanHost(savedHost.trim(), port: savedPort);
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() => _kept = kept);

    _wifiPeersSub = _wifiComms.peersStream.listen((peers) {
      if (!mounted) return;
      setState(() => _wifiPeers = peers);
    });

    _wifiMsgSub = _wifiComms.messagesStream.listen((m) {
      if (!mounted) return;
      final key = _k(_Transport.wifi, m.peerId);
      setState(() {
        _lastMsgByKey[key] = m;
        final list = _historyByKey.putIfAbsent(key, () => <ChatMessage>[]);
        list.add(m);
        if (!m.fromMe) {
          _unreadByKey[key] = (_unreadByKey[key] ?? 0) + 1;
        }
      });
    });

    if (_nearbyComms != null) {
      _nearbyPeersSub = _nearbyComms!.peersStream.listen((peers) {
        if (!mounted) return;
        setState(() => _nearbyPeers = peers);
      });

      _nearbyMsgSub = _nearbyComms!.messagesStream.listen((m) {
        if (!mounted) return;
        final key = _k(_Transport.nearby, m.peerId);
        setState(() {
          _lastMsgByKey[key] = m;
          final list = _historyByKey.putIfAbsent(key, () => <ChatMessage>[]);
          list.add(m);
          if (!m.fromMe) {
            _unreadByKey[key] = (_unreadByKey[key] ?? 0) + 1;
          }
        });
      });
    }

    try {
      await _bubbleDiscovery.start();
      _bubblesSub = _bubbleDiscovery.bubblesStream.listen((list) {
        if (!mounted) return;
        setState(() => _bubbles = list);
      });
    } catch (_) {}

    if (!isWeb) {
      try {
        if (isAndroid) {
          await AndroidMulticastLock.acquire();
        }
        await _lanDiscovery.startListening();
        _lanSub = _lanDiscovery.stream.listen((list) {
          if (!mounted) return;
          setState(() => _lanBubbles = list);
        });
      } catch (_) {}
    }

    await _ensurePermissions();
  }

  Future<void> _ensurePermissions() async {
    final ok = await PermissionsService.requestAll();

    bool locEnabled = await Geolocator.isLocationServiceEnabled();
    if (!locEnabled) {
      await Geolocator.openLocationSettings();
      locEnabled = await Geolocator.isLocationServiceEnabled();
    }

    if (!mounted) return;
    setState(() => _permissionsOk = ok && locEnabled);
  }

  @override
  void dispose() {
    _wifiPeersSub?.cancel();
    _wifiMsgSub?.cancel();
    _nearbyPeersSub?.cancel();
    _nearbyMsgSub?.cancel();

    _bubblesSub?.cancel();
    _bubbleDiscovery.stop();

    _lanSub?.cancel();
    _lanDiscovery.dispose();

    if (isAndroid) {
      AndroidMulticastLock.release();
    }

    _bubbleSession?.dispose();
    _bubbleSession = null;

    _wifiComms.dispose();
    _nearbyComms?.dispose();

    _bubbleService.stop();

    _displayNameCtrl.dispose();
    _peerSearchCtrl.dispose();
    _lanHostCtrl.dispose();
    _lanPortCtrl.dispose();

    _hostInviteCtrl.dispose();
    _hostPasswordCtrl.dispose();

    _livePulseCtrl.dispose();
    _ctaBreathCtrl.dispose();
    _pressCtrl.dispose();

    super.dispose();
  }

  Future<void> _pickProfileImage() async {
    try {
      final file = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (file == null) return;

      final bytes = await file.readAsBytes();
      final b64 = base64Encode(bytes);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kProfileImageB64Key, b64);

      if (!mounted) return;
      setState(() => _profileBytes = bytes);

      _wifiComms.setMyContactInfo(
          phone: _myPhone, handle: _myHandle, profileImageB64: b64);
      _nearbyComms?.setMyContactInfo(
          phone: _myPhone, handle: _myHandle, profileImageB64: b64);

      _showSnack('Profile photo updated.');
    } catch (_) {
      _showSnack('Could not pick that image.');
    }
  }

  Future<void> _removeProfileImage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kProfileImageB64Key);
    if (!mounted) return;
    setState(() => _profileBytes = null);

    _wifiComms.setMyContactInfo(
        phone: _myPhone, handle: _myHandle, profileImageB64: null);
    _nearbyComms?.setMyContactInfo(
        phone: _myPhone, handle: _myHandle, profileImageB64: null);

    _showSnack('Profile photo removed.');
  }

  Future<void> _startBubble() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      await _ensurePermissions();

      if (!_permissionsOk) {
        _showSnack('Turn on GPS and allow permissions to go live.');
        return;
      }

      final name = _displayNameCtrl.text.trim();
      if (name.isEmpty) {
        _showSnack('Set a display name first.');
        return;
      }

      // ✅ Ask privacy mode before going live
      final bubbleSettings = await _promptHostBubbleSettings();
      if (bubbleSettings == null) return;

      _clearSessionState();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kDisplayNameKey, name);

      final bubble = await _bubbleService.createBubble().timeout(
        const Duration(seconds: 12),
        onTimeout: () =>
        throw TimeoutException('Timed out creating bubble (GPS).'),
      );

      await _wifiComms
          .start(
        displayName: name,
        bubbleId: bubble.bubbleId,
        bubbleSettings: bubbleSettings,
      )
          .timeout(
        const Duration(seconds: 8),
        onTimeout: () =>
        throw TimeoutException('Timed out starting Wi-Fi comms.'),
      );

      if (_nearbyComms != null) {
        try {
          await _nearbyComms!
              .start(
            displayName: name,
            bubbleId: bubble.bubbleId,
            bubbleSettings: bubbleSettings,
          )
              .timeout(
            const Duration(seconds: 8),
            onTimeout: () => throw TimeoutException(
                'Timed out starting Nearby comms.'),
          );
        } catch (e) {
          _showSnack('Nearby not started: $e');
        }
      }

      // If hosting locally, broadcast UDP beacons
      if (!isWeb) {
        final hostingLocally = _lanHostCtrl.text.trim().isEmpty;
        if (hostingLocally) {
          try {
            await _lanDiscovery.startBroadcasting(
              bubbleId: bubble.bubbleId,
              displayName: name,
              port: 4040,
            );
          } catch (_) {}
        }
      }

      final eventPeerId =
          prefs.getString(_kEventPeerIdKey) ?? const Uuid().v4();
      await prefs.setString(_kEventPeerIdKey, eventPeerId);

      _bubbleSession?.dispose();
      _bubbleSession = BubbleSessionController(
        comms: [
          _wifiComms,
          if (_nearbyComms != null) _nearbyComms!,
        ],
        bubbleId: bubble.bubbleId,
        myDisplayName: name,
        myEventPeerId: eventPeerId,
      );

      await _bubbleService
          .startMonitoring(
        onUpdate: (pos, dist) {
          if (!mounted) return;
          setState(() {
            _latestPos = pos;
            _distanceFromCenter = dist;
          });
        },
        onExit: (pos, dist) async {
          if (!mounted) return;
          _showSnack('You left the bubble. Connections ended.');
          await _stopBubble();
        },
      )
          .timeout(
        const Duration(seconds: 8),
        onTimeout: () =>
        throw TimeoutException('Timed out starting GPS monitoring.'),
      );

      if (!mounted) return;
      setState(() {
        _latestPos = bubble.center;
        _distanceFromCenter = 0;
        _joinedBubbleId = bubble.bubbleId;
      });

      if (bubbleSettings.isPrivate) {
        final invite = bubbleSettings.inviteCode;
        final pwHint = bubbleSettings.requirePassword ? ' + password' : '';
        _showSnack('Private bubble live. Invite: $invite$pwHint');
      }
    } on TimeoutException catch (e) {
      _showSnack(e.message ?? 'Timed out going live.');
      await _safeStopIfPartiallyStarted();
    } catch (e) {
      _showSnack('Could not go live: $e');
      await _safeStopIfPartiallyStarted();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _safeStopIfPartiallyStarted() async {
    if (!isWeb) {
      try {
        await _lanDiscovery.stopBroadcasting();
      } catch (_) {}
    }

    try {
      await _wifiComms.stop();
    } catch (_) {}
    try {
      await _nearbyComms?.stop();
    } catch (_) {}
    try {
      await _bubbleService.stop();
    } catch (_) {}

    _bubbleSession?.dispose();
    _bubbleSession = null;
  }

  Future<void> _stopBubble() async {
    if (!isWeb) {
      try {
        await _lanDiscovery.stopBroadcasting();
      } catch (_) {}
    }

    await _wifiComms.stop();
    await _nearbyComms?.stop();
    await _bubbleService.stop();

    _bubbleSession?.dispose();
    _bubbleSession = null;

    if (!mounted) return;
    setState(() {
      _distanceFromCenter = null;
      _latestPos = null;
      _wifiPeers = const [];
      _nearbyPeers = const [];
      _clearSessionState();
    });
  }

  Future<void> _joinDiscoveredBubble(DiscoveredBubble b) async {
    if (_busy) return;

    final name = _displayNameCtrl.text.trim();
    if (name.isEmpty) {
      _showSnack('Set a display name first.');
      return;
    }

    if (b.host == null || b.port == null) {
      _showSnack('Bubble has no joinable host yet.');
      return;
    }

    final settings = await _promptJoinCredentials(bubbleName: b.bubbleName);
    if (settings == null) return;

    setState(() => _busy = true);

    try {
      _clearSessionState();

      if (!isWeb) {
        try {
          await _lanDiscovery.stopBroadcasting();
        } catch (_) {}
      }

      await _wifiComms.stop();
      await _nearbyComms?.stop();
      await _bubbleService.stop();

      await _wifiComms.setLanHost(b.host!, port: b.port!);
      await _wifiComms.start(
        displayName: name,
        bubbleId: b.bubbleId,
        bubbleSettings: settings,
      );

      final prefs = await SharedPreferences.getInstance();
      final eventPeerId =
          prefs.getString(_kEventPeerIdKey) ?? const Uuid().v4();
      await prefs.setString(_kEventPeerIdKey, eventPeerId);

      _bubbleSession?.dispose();
      _bubbleSession = BubbleSessionController(
        comms: [_wifiComms],
        bubbleId: b.bubbleId,
        myDisplayName: name,
        myEventPeerId: eventPeerId,
      );

      if (!mounted) return;
      setState(() {
        _joinedBubbleId = b.bubbleId;
        _distanceFromCenter = null;
        _latestPos = null;
      });

      _showSnack('Joined ${b.bubbleName}.');
    } catch (e) {
      _showSnack('Could not join bubble: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _joinLanAnnouncement(LanBubbleAnnouncement a) async {
    if (_busy) return;

    final name = _displayNameCtrl.text.trim();
    if (name.isEmpty) {
      _showSnack('Set a display name first.');
      return;
    }

    final settings = await _promptJoinCredentials(bubbleName: a.displayName);
    if (settings == null) return;

    setState(() => _busy = true);
    try {
      _clearSessionState();

      if (!isWeb) {
        try {
          await _lanDiscovery.stopBroadcasting();
        } catch (_) {}
      }

      await _wifiComms.stop();
      await _nearbyComms?.stop();
      await _bubbleService.stop();

      await _wifiComms.setLanHost(a.hostString, port: a.port);
      await _wifiComms.start(
        displayName: name,
        bubbleId: a.bubbleId,
        bubbleSettings: settings,
      );

      final prefs = await SharedPreferences.getInstance();
      final eventPeerId =
          prefs.getString(_kEventPeerIdKey) ?? const Uuid().v4();
      await prefs.setString(_kEventPeerIdKey, eventPeerId);

      _bubbleSession?.dispose();
      _bubbleSession = BubbleSessionController(
        comms: [_wifiComms],
        bubbleId: a.bubbleId,
        myDisplayName: name,
        myEventPeerId: eventPeerId,
      );

      if (!mounted) return;
      setState(() {
        _joinedBubbleId = a.bubbleId;
        _distanceFromCenter = null;
        _latestPos = null;
      });

      _showSnack('Joined ${a.displayName}.');
    } catch (e) {
      _showSnack('Could not join bubble: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _keepPeer(PeerProfile peer) async {
    final exists = _kept.any((c) => c.id == peer.endpointId);
    if (exists) {
      _showSnack('Already kept.');
      return;
    }

    final contact = KeptContact(
      id: peer.endpointId,
      displayName: peer.displayName,
      keptAt: DateTime.now(),
      phone: peer.phone,
      handle: peer.handle,
    );

    final updated = [contact, ..._kept];
    await _repo.save(updated);
    if (!mounted) return;

    setState(() => _kept = updated);
    _showSnack('Kept ${peer.displayName}.');
  }

  Future<void> _removeKept(KeptContact c) async {
    final updated = _kept.where((x) => x.id != c.id).toList();
    await _repo.save(updated);
    if (!mounted) return;
    setState(() => _kept = updated);
  }

  Future<void> _openChat(_Transport t, PeerProfile peer) async {
    final key = _k(t, peer.endpointId);
    setState(() => _unreadByKey.remove(key));

    final comms =
    (t == _Transport.wifi) ? _wifiComms : (_nearbyComms ?? _wifiComms);

    final initial =
    List<ChatMessage>.from(_historyByKey[key] ?? const <ChatMessage>[]);
    initial.sort((a, b) => a.at.compareTo(b.at));

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatPage(
          nearby: comms,
          peer: peer,
          initialMessages: initial,
        ),
      ),
    );

    if (!mounted) return;
    setState(() => _unreadByKey.remove(key));
  }

  Future<void> _editMyContactInfo() async {
    final phoneCtrl = TextEditingController(text: _myPhone ?? '');
    final handleCtrl = TextEditingController(text: _myHandle ?? '');

    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Your contact info'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Optional. If filled, people in your bubble can save it when they tap Keep.',
                style:
                TextStyle(color: Colors.black.withOpacity(0.65), fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone number (optional)',
                  hintText: '+233 ...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: handleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Social handle (optional)',
                  hintText: '@instagram / @x / WhatsApp',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                phoneCtrl.clear();
                handleCtrl.clear();
              },
              child: const Text('Clear'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _brandGreen,
                foregroundColor: Colors.white,
                elevation: 0,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (res != true) return;

    final phone = phoneCtrl.text.trim();
    final handle = handleCtrl.text.trim();

    final prefs = await SharedPreferences.getInstance();
    if (phone.isEmpty) {
      await prefs.remove(_kPhoneKey);
    } else {
      await prefs.setString(_kPhoneKey, phone);
    }
    if (handle.isEmpty) {
      await prefs.remove(_kHandleKey);
    } else {
      await prefs.setString(_kHandleKey, handle);
    }

    _myPhone = phone.isEmpty ? null : phone;
    _myHandle = handle.isEmpty ? null : handle;

    final rawImgB64 = prefs.getString(_kProfileImageB64Key);
    final profileImageB64 =
    (rawImgB64 == null || rawImgB64.trim().isEmpty) ? null : rawImgB64.trim();

    _wifiComms.setMyContactInfo(
        phone: _myPhone, handle: _myHandle, profileImageB64: profileImageB64);
    _nearbyComms?.setMyContactInfo(
        phone: _myPhone, handle: _myHandle, profileImageB64: profileImageB64);

    if (!mounted) return;
    setState(() {});
    _showSnack('Contact info updated.');
  }

  Future<void> _pickSortMode() async {
    final selected = await showModalBottomSheet<_PeerSortMode>(
      context: context,
      backgroundColor: Colors.white,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 6),
              ListTile(
                leading: const Icon(Icons.schedule),
                title: const Text('Sorted by: Time'),
                subtitle: const Text('First seen'),
                onTap: () => Navigator.of(ctx).pop(_PeerSortMode.firstSeen),
              ),
              ListTile(
                leading: const Icon(Icons.sort_by_alpha),
                title: const Text('Sorted by: Name'),
                subtitle: const Text('A → Z'),
                onTap: () => Navigator.of(ctx).pop(_PeerSortMode.name),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );

    if (selected == null) return;
    setState(() => _sortMode = selected);
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _openBubbleFeaturesIfAvailable() {
    final c = _bubbleSession;
    if (c == null) {
      _showSnack('Go live or Join a bubble first.');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => BubblePage(controller: c)),
    );
  }

  void _openGuide() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GuidePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bubble = _bubbleService.state;

    final commsRunning =
        _wifiComms.isRunning || (_nearbyComms?.isRunning ?? false);
    final hasAnyBubble = (bubble?.bubbleId != null) || (_joinedBubbleId != null);
    final inBubble = commsRunning && hasAnyBubble;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('Echo'),
          actions: [
            IconButton(
              tooltip: 'Guide',
              onPressed: _openGuide,
              icon: const Icon(Icons.help_outline),
            ),
            IconButton(
              tooltip: 'Bubble features',
              onPressed:
              _bubbleSession == null ? null : _openBubbleFeaturesIfAvailable,
              icon: const Icon(Icons.bubble_chart_outlined),
            ),
          ],
          bottom: TabBar(
            indicatorColor: _brandGreen,
            labelColor: Colors.black,
            unselectedLabelColor: Colors.black.withOpacity(0.55),
            tabs: const [
              Tab(text: 'Here & Now', icon: Icon(Icons.wifi_tethering)),
              Tab(text: 'Kept', icon: Icon(Icons.bookmark)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildHereNow(context, inBubble, bubble),
            KeptPage(contacts: _kept, onRemove: _removeKept),
          ],
        ),
      ),
    );
  }

  Widget _buildHereNow(BuildContext context, bool inBubble, BubbleState? bubble) {
    final dist = _distanceFromCenter;
    final progress = dist == null ? 0.0 : (dist / _radiusM).clamp(0.0, 1.0);

    String safetyTitle;
    String safetySubtitle;
    if (progress < 0.70) {
      safetyTitle = 'You are safely inside the bubble';
      safetySubtitle =
      dist == null ? 'Centering…' : '${dist.toStringAsFixed(1)} m from center';
    } else if (progress < 0.90) {
      safetyTitle = 'You’re close to the edge';
      safetySubtitle =
      dist == null ? 'Be careful…' : '${dist.toStringAsFixed(1)} m from center';
    } else {
      safetyTitle = 'Edge warning';
      safetySubtitle =
      dist == null ? 'Almost out…' : '${dist.toStringAsFixed(1)} m from center';
    }

    final q = _peerSearchCtrl.text.trim().toLowerCase();

    List<_PeerEntry> wifi =
    _wifiPeers.map((p) => _PeerEntry(transport: _Transport.wifi, peer: p)).toList();
    List<_PeerEntry> nearby =
    _nearbyPeers.map((p) => _PeerEntry(transport: _Transport.nearby, peer: p)).toList();

    if (q.isNotEmpty) {
      wifi = wifi.where((e) => e.peer.displayName.toLowerCase().contains(q)).toList();
      nearby =
          nearby.where((e) => e.peer.displayName.toLowerCase().contains(q)).toList();
    }

    int cmp(_PeerEntry a, _PeerEntry b) {
      if (_sortMode == _PeerSortMode.name) {
        return a.peer.displayName
            .toLowerCase()
            .compareTo(b.peer.displayName.toLowerCase());
      }
      return a.peer.firstSeen.compareTo(b.peer.firstSeen);
    }

    wifi.sort(cmp);
    nearby.sort(cmp);

    final myName = _displayNameCtrl.text.trim().isEmpty
        ? 'Set your name'
        : _displayNameCtrl.text.trim();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (isDesktop) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.black.withOpacity(0.06)),
            ),
            child: Text(
              'Note: Hosting bubbles from PC is limited right now. '
                  'For the most reliable discovery, host from Android; PC devices can join.',
              style: TextStyle(
                color: Colors.black.withOpacity(0.75),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.black.withOpacity(0.06)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Your bubble',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                    ),
                    _PermIndicator(ok: _permissionsOk),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'Your contact info',
                      onPressed: _editMyContactInfo,
                      icon: Icon(Icons.contact_page_outlined,
                          color: Colors.black.withOpacity(0.75)),
                    ),
                    IconButton(
                      tooltip: _showDebug ? 'Hide info' : 'Info',
                      onPressed: () => setState(() => _showDebug = !_showDebug),
                      icon: Icon(Icons.info_outline,
                          color: Colors.black.withOpacity(0.75)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _stateHeroPill(inBubble: inBubble),
                const SizedBox(height: 14),
                _radiusPill(),
                const SizedBox(height: 10),

                if (!inBubble)
                  Text(
                    'You’re invisible for now.\nGo live or Join a bubble to see who’s nearby.',
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.64),
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  Text(
                    'You’re visible to people nearby.',
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.60),
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                if (_showDebug) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Bubble ID: ${bubble?.bubbleId ?? _joinedBubbleId ?? '-'}',
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.45),
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],

                const SizedBox(height: 16),
                if (!inBubble) ...[
                  Text(
                    'Distance will be tracked once you’re live (GPS bubble).',
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.50),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ] else if (_distanceFromCenter != null) ...[
                  Text(
                    safetyTitle,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    safetySubtitle,
                    style: TextStyle(color: Colors.black.withOpacity(0.60)),
                  ),
                  const SizedBox(height: 10),
                  _distanceBar(progress: progress, inBubble: true),
                ],

                const SizedBox(height: 18),

                if (!inBubble) ...[
                  Row(
                    children: [
                      _myAvatar(size: 44),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Profile photo',
                          style: TextStyle(
                            color: Colors.black.withOpacity(0.80),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _pickProfileImage,
                        icon: const Icon(Icons.upload_outlined),
                        label: const Text('Upload'),
                      ),
                      if (_profileBytes != null)
                        IconButton(
                          tooltip: 'Remove',
                          onPressed: _removeProfileImage,
                          icon: const Icon(Icons.delete_outline),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _displayNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Your display name',
                      hintText: 'e.g., Alex',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ✅ Default host mode row (THIS is the private-host option)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _softField,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.black.withOpacity(0.06)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _hostPrivate ? Icons.lock_outline : Icons.public,
                          color: Colors.black.withOpacity(0.70),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _hostPrivate
                                ? 'Default host mode: Private${_hostRequirePassword ? " + password" : ""}'
                                : 'Default host mode: Public',
                            style: TextStyle(
                              color: Colors.black.withOpacity(0.70),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            await _promptHostBubbleSettings();
                            if (!mounted) return;
                            setState(() {});
                          },
                          child: const Text('Edit'),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Row(
                    children: [
                      _myAvatar(size: 44),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              myName,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w800),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Visible to people in this bubble',
                              style:
                              TextStyle(color: Colors.black.withOpacity(0.60)),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Change photo',
                        onPressed: _pickProfileImage,
                        icon: const Icon(Icons.photo_camera_outlined),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 16),
                _ctaButton(inBubble: inBubble),

                if (inBubble) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _bubbleSession == null
                          ? null
                          : _openBubbleFeaturesIfAvailable,
                      icon: const Icon(Icons.bubble_chart_outlined),
                      label: const Text('Open bubble features'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: 18),
        _bubblesNearbyCard(inBubble: inBubble),
        const SizedBox(height: 18),

        Opacity(
          opacity: inBubble ? 1 : 0.55,
          child: IgnorePointer(
            ignoring: !inBubble,
            child: TextField(
              controller: _peerSearchCtrl,
              decoration: InputDecoration(
                labelText: inBubble
                    ? 'Search people in this bubble'
                    : 'Go live or Join to search people',
                hintText: inBubble ? 'Type a name…' : null,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _peerSearchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                  tooltip: 'Clear',
                  onPressed: () => setState(() => _peerSearchCtrl.clear()),
                  icon: const Icon(Icons.clear),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),

        const SizedBox(height: 14),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'People here (${wifi.length + nearby.length})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            _sortHeaderChip(inBubble: inBubble),
          ],
        ),

        const SizedBox(height: 10),

        if (!inBubble)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              '👀 Not in a bubble yet.\nGo live or Join to see people.',
              textAlign: TextAlign.center,
              style:
              TextStyle(color: Colors.black.withOpacity(0.70), height: 1.25),
            ),
          ),

        if (inBubble) ...[
          _sectionHeader(
            icon: Icons.wifi,
            title: 'Wi-Fi peers',
            subtitle: 'Same network (LAN)',
            count: wifi.length,
          ),
          const SizedBox(height: 8),
          if (wifi.isEmpty)
            _emptySectionHint('No Wi-Fi peers yet.')
          else
            _peersCard(wifi),
          const SizedBox(height: 14),
        ],

        if (inBubble) ...[
          _sectionHeader(
            icon: Icons.bluetooth_searching,
            title: 'Nearby peers',
            subtitle: _nearbyComms == null
                ? 'Not supported on this device'
                : 'Bluetooth / Nearby Connections',
            count: nearby.length,
            disabled: _nearbyComms == null,
          ),
          const SizedBox(height: 8),
          if (_nearbyComms == null)
            _emptySectionHint(
                'Nearby is only available on Android (Nearby Connections).')
          else if (nearby.isEmpty)
            _emptySectionHint('No Nearby peers yet.')
          else
            _peersCard(nearby),
          const SizedBox(height: 18),
        ],

        Container(
          decoration: BoxDecoration(
            color: _softField,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.all(14),
          child: Text(
            'Privacy reassurance:\n'
                '• Your bubble is local and temporary.\n'
                '• When you leave, connections vanish.\n'
                '• Private bubbles can be invite-only or invite + password.',
            style: TextStyle(
              color: Colors.black.withOpacity(0.60),
              height: 1.25,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),

        const SizedBox(height: 40),
      ],
    );
  }

  Widget _bubblesNearbyCard({required bool inBubble}) {
    if (isWeb) return const SizedBox.shrink();

    final nsd = _bubbles;
    final udp = _lanBubbles;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Bubbles nearby',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(
            'Tap Join to enter an active bubble on this Wi-Fi network.',
            style: TextStyle(
                color: Colors.black.withOpacity(0.60),
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),

          if (nsd.isEmpty && udp.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _softField,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.black.withOpacity(0.06)),
              ),
              child: Text(
                'No active bubbles found yet.\n'
                    'Tip: Have one device press Go live (host), then others can Join.',
                style: TextStyle(
                    color: Colors.black.withOpacity(0.65),
                    fontWeight: FontWeight.w700,
                    height: 1.25),
              ),
            ),

          ...nsd.take(6).map((b) {
            final joined = _joinedBubbleId == b.bubbleId;
            final joinable = (b.host != null && b.port != null);

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _softField,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.black.withOpacity(0.06)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bubble_chart_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(b.bubbleName,
                            style: const TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 2),
                        Text(
                          '${b.peopleCountEstimate} active device(s) • ${joinable ? "joinable" : "no host yet"}',
                          style: TextStyle(
                              color: Colors.black.withOpacity(0.60),
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                      joined ? Colors.black.withOpacity(0.12) : _brandGreen,
                      foregroundColor:
                      joined ? Colors.black.withOpacity(0.70) : Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: (_busy || joined || !joinable)
                        ? null
                        : () => _joinDiscoveredBubble(b),
                    child: Text(joined ? 'Joined' : 'Join',
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
            );
          }),

          if (udp.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Direct LAN hosts',
              style: TextStyle(
                  color: Colors.black.withOpacity(0.65),
                  fontWeight: FontWeight.w900,
                  fontSize: 12),
            ),
            const SizedBox(height: 8),
            ...udp.take(6).map((a) {
              final joined = _joinedBubbleId == a.bubbleId;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _softField,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.black.withOpacity(0.06)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.router_outlined),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.displayName,
                              style: const TextStyle(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 2),
                          Text(
                            '${a.hostString}:${a.port} • ${a.bubbleId}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Colors.black.withOpacity(0.60),
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: joined
                            ? Colors.black.withOpacity(0.12)
                            : _brandGreen,
                        foregroundColor: joined
                            ? Colors.black.withOpacity(0.70)
                            : Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: (_busy || joined)
                          ? null
                          : () => _joinLanAnnouncement(a),
                      child: Text(joined ? 'Joined' : 'Join',
                          style: const TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ],
                ),
              );
            }),
          ],

          if (!inBubble)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Note: “People here” only fills after you Go live or Join a bubble.',
                style: TextStyle(
                    color: Colors.black.withOpacity(0.55),
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    required int count,
    bool disabled = false,
  }) {
    return Row(
      children: [
        Icon(icon,
            color: disabled
                ? Colors.black.withOpacity(0.35)
                : Colors.black.withOpacity(0.75)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: disabled ? Colors.black.withOpacity(0.35) : Colors.black,
                ),
              ),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.black.withOpacity(disabled ? 0.30 : 0.55))),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.04),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.black.withOpacity(0.06)),
          ),
          child: Text(
            '$count',
            style: TextStyle(
                fontWeight: FontWeight.w900,
                color: Colors.black.withOpacity(disabled ? 0.35 : 0.75)),
          ),
        ),
      ],
    );
  }

  Widget _emptySectionHint(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _softField,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Text(text,
          style: TextStyle(
              color: Colors.black.withOpacity(0.60),
              fontWeight: FontWeight.w700)),
    );
  }

  Widget _peersCard(List<_PeerEntry> peers) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.black.withOpacity(0.06)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: peers.length,
        separatorBuilder: (_, __) =>
            Divider(height: 1, color: Colors.black.withOpacity(0.06)),
        itemBuilder: (context, i) {
          final e = peers[i];
          final p = e.peer;

          final key = _k(e.transport, p.endpointId);
          final unread = _unreadByKey[key] ?? 0;
          final last = _lastMsgByKey[key];
          final preview = last == null
              ? 'Tap to chat'
              : (last.fromMe ? 'You: ${last.text}' : last.text);

          final chipText = e.transport == _Transport.wifi ? 'Wi-Fi' : 'Nearby';
          final chipIcon =
          e.transport == _Transport.wifi ? Icons.wifi : Icons.bluetooth;

          final avatar = _peerAvatarProvider(p);

          return ListTile(
            onTap: () => _openChat(e.transport, p),
            leading: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  backgroundColor: _softField,
                  backgroundImage: avatar,
                  child: avatar == null
                      ? Text(
                    p.displayName.isEmpty
                        ? '?'
                        : p.displayName.characters.first.toUpperCase(),
                    style: TextStyle(
                        color: Colors.black.withOpacity(0.75),
                        fontWeight: FontWeight.w900),
                  )
                      : null,
                ),
                if (unread > 0)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: _badge(unread),
                  ),
              ],
            ),
            title: Row(
              children: [
                Expanded(
                    child: Text(p.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w800))),
                const SizedBox(width: 8),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.black.withOpacity(0.06)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(chipIcon,
                          size: 14, color: Colors.black.withOpacity(0.65)),
                      const SizedBox(width: 6),
                      Text(
                        chipText,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: Colors.black.withOpacity(0.65),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            subtitle: Text(
              preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.black.withOpacity(0.55)),
            ),
            trailing: TextButton.icon(
              onPressed: () => _keepPeer(p),
              icon: Icon(Icons.bookmark_add_outlined, color: _brandGreen),
              label: const Text('Keep'),
            ),
          );
        },
      ),
    );
  }

  // ===================== UI Parts =====================

  Widget _myAvatar({double size = 40}) {
    final img = _profileBytes;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: _softField,
      backgroundImage: img == null ? null : MemoryImage(img),
      child: img == null
          ? Icon(Icons.person, color: Colors.black.withOpacity(0.70))
          : null,
    );
  }

  Widget _radiusPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _softField,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.my_location,
              size: 16, color: Colors.black.withOpacity(0.70)),
          const SizedBox(width: 8),
          Text(
            'Radius ${_radiusM.toStringAsFixed(0)} m',
            style: TextStyle(
                color: Colors.black.withOpacity(0.70),
                fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _stateHeroPill({required bool inBubble}) {
    if (!inBubble) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.black.withOpacity(0.12)),
          color: Colors.black.withOpacity(0.02),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle_outlined,
                size: 20, color: Colors.black.withOpacity(0.65)),
            const SizedBox(width: 10),
            Text(
              'Bubble inactive',
              style: TextStyle(
                  color: Colors.black.withOpacity(0.80),
                  fontWeight: FontWeight.w900,
                  fontSize: 16),
            ),
          ],
        ),
      );
    }

    return AnimatedBuilder(
      animation: _livePulseCtrl,
      builder: (context, _) {
        final t = _livePulseCtrl.value;
        final glow = 0.12 + (t * 0.18);
        final scale = 0.985 + (t * 0.015);

        return Transform.scale(
          scale: scale,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: _liveRed,
              boxShadow: [
                BoxShadow(
                  color: _liveRed.withOpacity(glow),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FadeTransition(
                  opacity: Tween<double>(begin: 0.35, end: 1.0)
                      .animate(_livePulseCtrl),
                  child: const Icon(Icons.circle,
                      size: 12, color: Colors.white),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Live now',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _distanceBar({required double progress, required bool inBubble}) {
    final safe = _brandGreen;
    final danger = _liveRed;

    final t = (progress - 0.65).clamp(0.0, 1.0);
    final valueColor = Color.lerp(safe, danger, t) ?? safe;

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: inBubble ? progress : 0,
        minHeight: 10,
        backgroundColor: Colors.black.withOpacity(0.06),
        valueColor: AlwaysStoppedAnimation(valueColor),
      ),
    );
  }

  Widget _ctaButton({required bool inBubble}) {
    final label = _busy ? 'Starting…' : (inBubble ? 'Leave bubble' : 'Go live');
    final icon = inBubble ? Icons.logout : Icons.play_arrow;
    final bg = inBubble ? _liveRed : _brandGreen;

    return AnimatedBuilder(
      animation: Listenable.merge([_pressCtrl, _ctaBreathCtrl]),
      builder: (context, _) {
        final pressScale = 1.0 - (_pressCtrl.value * 0.02);
        final breath = inBubble ? (1.0 - (_ctaBreathCtrl.value * 0.01)) : 1.0;
        final scale = pressScale * breath;

        final shadowOpacity =
        inBubble ? (0.10 + (_ctaBreathCtrl.value * 0.06)) : 0.08;

        return Transform.scale(
          scale: scale,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: bg.withOpacity(shadowOpacity),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: SizedBox(
              height: 56,
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: bg,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _busy
                    ? null
                    : () async {
                  await _pressCtrl.forward();
                  await _pressCtrl.reverse();
                  if (inBubble) {
                    await _stopBubble();
                  } else {
                    await _startBubble();
                  }
                },
                icon: Icon(icon),
                label:
                Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _sortHeaderChip({required bool inBubble}) {
    if (!inBubble) return const SizedBox.shrink();

    final label = _sortMode == _PeerSortMode.firstSeen ? 'Time' : 'Name';
    final icon = _sortMode == _PeerSortMode.firstSeen
        ? Icons.schedule
        : Icons.sort_by_alpha;

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: _pickSortMode,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: _softField,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.black.withOpacity(0.06)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.black.withOpacity(0.70)),
            const SizedBox(width: 6),
            Text('Sort: $label',
                style: TextStyle(
                    color: Colors.black.withOpacity(0.70),
                    fontWeight: FontWeight.w700)),
            Icon(Icons.arrow_drop_down, color: Colors.black.withOpacity(0.70)),
          ],
        ),
      ),
    );
  }

  Widget _badge(int count) {
    final text = count > 99 ? '99+' : '$count';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration:
      BoxDecoration(color: _liveRed, borderRadius: BorderRadius.circular(999)),
      child: Text(text,
          style: const TextStyle(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
    );
  }
}

class _PermIndicator extends StatelessWidget {
  final bool ok;
  const _PermIndicator({required this.ok});

  @override
  Widget build(BuildContext context) {
    final color = ok ? _HomePageState._brandGreen : Colors.orange;
    final icon = ok ? Icons.verified_outlined : Icons.warning_amber_outlined;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(ok ? 'OK' : 'Fix',
              style: TextStyle(
                  color: Colors.black.withOpacity(0.75),
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}