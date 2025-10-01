import 'package:flutter/foundation.dart' show kIsWeb;

bool get isWeb => kIsWeb;

// On web (and other non-io targets), everything else is false.
bool get isAndroid => false;
bool get isIOS => false;

bool get isWindows => false;
bool get isMacOS => false;
bool get isLinux => false;
bool get isDesktop => false;

bool get isMobile => false;