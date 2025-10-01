import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

bool get isWeb => kIsWeb;

bool get isAndroid => !kIsWeb && Platform.isAndroid;
bool get isIOS => !kIsWeb && Platform.isIOS;

bool get isWindows => !kIsWeb && Platform.isWindows;
bool get isMacOS => !kIsWeb && Platform.isMacOS;
bool get isLinux => !kIsWeb && Platform.isLinux;

bool get isDesktop => !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
bool get isMobile => isAndroid || isIOS;