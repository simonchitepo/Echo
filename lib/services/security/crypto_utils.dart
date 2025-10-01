import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class CryptoUtils {
  static final Random _rng = Random.secure();

  // Algorithms
  static final Cipher cipher = AesGcm.with256bits();
  static final MacAlgorithm hmac = Hmac.sha256();

  // ✅ Use concrete Pbkdf2 type (avoids KeyDerivationAlgorithm mismatch across versions)
  static final Pbkdf2 pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 120000,
    bits: 256,
  );

  /// Secure random bytes.
  static Uint8List randomBytes(int len) {
    final out = Uint8List(len);
    for (int i = 0; i < len; i++) {
      out[i] = _rng.nextInt(256);
    }
    return out;
  }

  /// Base64URL helpers (safe to transport in JSON).
  static String b64(Uint8List bytes) => base64UrlEncode(bytes);
  static Uint8List b64d(String s) => Uint8List.fromList(base64Url.decode(s));

  /// Constant-time equality check for MAC/proof comparisons.
  static bool constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= (a[i] ^ b[i]);
    }
    return diff == 0;
  }

  /// Derive a password key (never store the password).
  ///
  /// - `salt` must be random and unique per bubble/session.
  /// - PBKDF2 with SHA-256, 120k iterations, 256-bit output.
  static Future<SecretKey> derivePasswordKey({
    required String password,
    required Uint8List salt,
  }) async {
    final pwBytes = utf8.encode(password);
    return pbkdf2.deriveKey(
      secretKey: SecretKey(pwBytes),
      nonce: salt,
    );
  }

  /// Make an HMAC proof for join challenge:
  /// HMAC(pwKey, bubbleId || 0x00 || clientNonce || 0x00 || hostNonce)
  static Future<Uint8List> makeJoinProof({
    required SecretKey passwordKey,
    required String bubbleId,
    required Uint8List clientNonce,
    required Uint8List hostNonce,
  }) async {
    final data = <int>[
      ...utf8.encode(bubbleId),
      0,
      ...clientNonce,
      0,
      ...hostNonce,
    ];
    final mac = await hmac.calculateMac(data, secretKey: passwordKey);
    return Uint8List.fromList(mac.bytes);
  }

  /// HKDF-SHA256: derive a session key from an input secret + context.
  ///
  /// - `ikm` = input keying material (nonces + optional secret)
  /// - `salt` = random salt (recommended)
  /// - `info` = context string (binds key to purpose)
  static Future<SecretKey> hkdf({
    required Uint8List ikm,
    required Uint8List salt,
    required String info,
    int bits = 256,
  }) async {
    final hk = Hkdf(
      hmac: Hmac.sha256(),
      outputLength: bits ~/ 8,
    );

    return hk.deriveKey(
      secretKey: SecretKey(ikm),
      nonce: salt,
      info: utf8.encode(info),
    );
  }

  /// Encrypt JSON using AES-GCM.
  ///
  /// Output payload format: nonce(12) || ciphertext || mac(16)
  static Future<Uint8List> encryptJson({
    required Map<String, dynamic> json,
    required SecretKey key,
    required String aad,
  }) async {
    final plaintext = utf8.encode(jsonEncode(json));
    final nonce = randomBytes(12);

    final secretBox = await cipher.encrypt(
      plaintext,
      secretKey: key,
      nonce: nonce,
      aad: utf8.encode(aad),
    );

    final out = BytesBuilder()
      ..add(nonce)
      ..add(secretBox.cipherText)
      ..add(secretBox.mac.bytes);
    return out.toBytes();
  }

  /// Decrypt JSON previously encrypted by [encryptJson].
  static Future<Map<String, dynamic>> decryptJson({
    required Uint8List payload,
    required SecretKey key,
    required String aad,
  }) async {
    // AES-GCM: 12-byte nonce, 16-byte tag
    if (payload.length < 12 + 16) {
      throw Exception('Ciphertext too short');
    }

    final nonce = payload.sublist(0, 12);
    final macBytes = payload.sublist(payload.length - 16);
    final cipherText = payload.sublist(12, payload.length - 16);

    final box = SecretBox(
      cipherText,
      nonce: nonce,
      mac: Mac(macBytes),
    );

    final clear = await cipher.decrypt(
      box,
      secretKey: key,
      aad: utf8.encode(aad),
    );

    final decoded = jsonDecode(utf8.decode(clear));
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Decrypted payload is not a JSON map');
    }
    return decoded;
  }

  // ---------------------------------------------------------------------------
  // Convenience helpers (useful in LanCommsService)
  // ---------------------------------------------------------------------------

  /// Encrypt a plain string into a base64url payload using AES-GCM JSON wrapper.
  static Future<String> encryptTextB64({
    required String text,
    required SecretKey key,
    required String aad,
  }) async {
    final bytes = await encryptJson(
      json: {'t': text},
      key: key,
      aad: aad,
    );
    return b64(bytes);
  }

  /// Decrypt a base64url payload (created by [encryptTextB64]) into a string.
  static Future<String> decryptTextB64({
    required String payloadB64,
    required SecretKey key,
    required String aad,
  }) async {
    final payload = b64d(payloadB64);
    final map = await decryptJson(payload: payload, key: key, aad: aad);
    final t = map['t'];
    return (t is String) ? t : '';
  }

  /// Safely extract bytes from a SecretKey (handy for debugging/derivation).
  static Future<Uint8List> secretKeyBytes(SecretKey key) async {
    final bytes = await key.extractBytes();
    return Uint8List.fromList(bytes);
  }
}