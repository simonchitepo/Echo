import 'package:flutter/foundation.dart' show kIsWeb;

import 'dart:io' show Platform;
import 'package:permission_handler/permission_handler.dart';

class PermissionsService {
  /// Requests only permissions that make sense for the current OS.
  /// Returns true if the required ones are granted.
  static Future<bool> requestAll() async {
    // Web: permission_handler does not support permission prompts reliably.
    // Geolocator / browser APIs will prompt when position is requested.
    if (kIsWeb) return true;

    // Helper: treat limited/restricted as OK (OEM ROM quirks)
    bool ok(PermissionStatus s) =>
        s.isGranted || s.isLimited || s.isRestricted;

    // 1) Location is REQUIRED for your "bubble" logic + Nearby scanning on Android.
    // This maps to FINE/COARSE as needed.
    final loc = await Permission.location.request();
    if (!ok(loc)) return false;

    // iOS / Desktop: if location is granted, we're good.
    if (!Platform.isAndroid) return true;

    // 2) Android: Bluetooth runtime permissions are required on Android 12+ (SDK 31+).
    // permission_handler will no-op on older Android versions.
    final btScan = await Permission.bluetoothScan.request();
    final btConnect = await Permission.bluetoothConnect.request();
    final btAdvertise = await Permission.bluetoothAdvertise.request();

    // If any are denied, don't hard-block the whole app.
    // Nearby may degrade, but LAN/Wi-Fi can still work.
    if (!ok(btScan) || !ok(btConnect) || !ok(btAdvertise)) {
      // If you prefer strict mode (block when denied), change to: return false;
      return true;
    }

    // 3) Android 13+ (SDK 33+) only. Typically ignored on Android 12 and below.
    // Don't fail the whole flow if denied.
    await Permission.nearbyWifiDevices.request();

    return true;
  }
}