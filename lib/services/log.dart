import 'package:flutter/foundation.dart';

void logInfo(String msg) {
  if (kDebugMode) {
    // ignore: avoid_print
    print('[Echo] $msg');
  }
}
