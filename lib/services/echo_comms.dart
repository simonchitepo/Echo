import 'dart:async';

import '../models/bubble_event.dart';
import '../models/bubble_settings.dart'; // ✅ NEW: public/private + invite/password
import '../models/chat_message.dart';
import '../models/peer_profile.dart';

/// Common interface for Echo device-to-device comms.
///
/// Implementations:
/// - NearbyService on Android (Nearby Connections).
/// - LanCommsService on Desktop + Web (WebSocket over LAN).
abstract class EchoComms {
  Stream<List<PeerProfile>> get peersStream;
  Stream<ChatMessage> get messagesStream;
  Stream<BubbleEvent> get eventsStream;

  bool get isRunning;

  /// Optional contact info you can choose to share with people in the bubble.
  /// Includes optional profile image (base64, typically jpeg/png).
  void setMyContactInfo({String? phone, String? handle, String? profileImageB64});

  /// Starts discovery/hosting and/or connects to a host (implementation-specific).
  ///
  /// ✅ bubbleSettings:
  /// - public: anyone can join
  /// - private: invite-only (and optional password)
  Future<void> start({
    required String displayName,
    required String bubbleId,
    BubbleSettings? bubbleSettings,
  });

  Future<void> stop();
  Future<void> dispose();

  /// Sends a chat message to a specific peer.
  Future<void> sendMessage(String peerId, String text);

  /// Sends a real-time bubble event (poll, shout, pulse, canvas, etc.).
  /// Use `toPeerId='*'` for broadcast.
  Future<void> sendEvent(BubbleEvent event, {String toPeerId = '*'});

  /// Optional: LAN-only helper. No-op on other transports.
  Future<void> setLanHost(String host, {int port});
}