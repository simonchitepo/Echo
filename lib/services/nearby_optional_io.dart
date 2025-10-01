import 'dart:io' show Platform;

import 'echo_comms.dart';
import 'nearby_service.dart';

/// IO platforms: Nearby only on Android.
EchoComms? createNearbyOptionalComms() {
  if (Platform.isAndroid) return NearbyService();
  return null;
}