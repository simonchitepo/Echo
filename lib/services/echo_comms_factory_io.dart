import 'dart:io' show Platform;

import 'echo_comms.dart';
import 'lan/lan_comms_service.dart';
import 'nearby_service.dart';

/// IO platforms factory (Windows/macOS/Linux/Android/iOS).
///
/// Transport selection:
/// - Android  => Nearby Connections (Bluetooth/Wi-Fi Direct / etc. via Google Nearby)
/// - Windows/macOS/Linux/iOS => LAN WebSocket transport (Wi-Fi / LAN)
///
/// Notes:
/// - Nearby Connections does NOT support Windows.
/// - LAN transport requires a host (or add auto-discovery via NSD/mDNS).
EchoComms createEchoCommsImpl() {
  // Android => Nearby (device-to-device)
  if (Platform.isAndroid) {
    return NearbyService();
  }

  // Desktop + iOS => LAN
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux || Platform.isIOS) {
    return LanCommsService();
  }

  // Fallback
  return LanCommsService();
}