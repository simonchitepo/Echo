import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'crypto_utils.dart';

class PasswordStore {
  static const _storage = FlutterSecureStorage();

  static String _saltKey(String bubbleId) => 'echo_pw_salt_$bubbleId';
  static String _verKey(String bubbleId) => 'echo_pw_ver_$bubbleId';

  /// Save verifier for this bubble.
  /// verifier = HMAC(pwKey, "echo-verifier")
  static Future<void> saveVerifier({
    required String bubbleId,
    required Uint8List salt,
    required Uint8List verifier,
  }) async {
    await _storage.write(key: _saltKey(bubbleId), value: CryptoUtils.b64(salt));
    await _storage.write(key: _verKey(bubbleId), value: CryptoUtils.b64(verifier));
  }

  static Future<(Uint8List salt, Uint8List verifier)?> readVerifier(String bubbleId) async {
    final s = await _storage.read(key: _saltKey(bubbleId));
    final v = await _storage.read(key: _verKey(bubbleId));
    if (s == null || v == null) return null;
    return (CryptoUtils.b64d(s), CryptoUtils.b64d(v));
  }

  static Future<void> clearVerifier(String bubbleId) async {
    await _storage.delete(key: _saltKey(bubbleId));
    await _storage.delete(key: _verKey(bubbleId));
  }
}