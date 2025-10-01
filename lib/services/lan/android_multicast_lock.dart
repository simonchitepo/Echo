import 'package:flutter/services.dart';
import '../platform_info.dart';

class AndroidMulticastLock {
  static const MethodChannel _ch = MethodChannel('echo.lan/multicast');

  static Future<void> acquire() async {
    if (!isAndroid) return;
    try {
      final ok = await _ch.invokeMethod<bool>('acquire');
      // ignore: avoid_print
      print('[Echo] MulticastLock acquire -> $ok');
    } catch (e) {
      // ignore: avoid_print
      print('[Echo] MulticastLock acquire FAILED: $e');
    }
  }

  static Future<void> release() async {
    if (!isAndroid) return;
    try {
      final ok = await _ch.invokeMethod<bool>('release');
      // ignore: avoid_print
      print('[Echo] MulticastLock release -> $ok');
    } catch (e) {
      // ignore: avoid_print
      print('[Echo] MulticastLock release FAILED: $e');
    }
  }
}