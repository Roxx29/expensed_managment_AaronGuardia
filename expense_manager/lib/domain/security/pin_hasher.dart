import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// PIN rules: 4–12 digits (6 recommended).
bool isValidPin(String pin) => RegExp(r'^\d{4,12}$').hasMatch(pin);

/// Failed attempts allowed before the first lockout.
const freeAttempts = 5;

/// 0 below [freeAttempts] failures, then 30 s doubling per further failure,
/// capped at 1 hour.
Duration lockoutFor(int failedAttempts) {
  if (failedAttempts < freeAttempts) return Duration.zero;
  final doublings = min(failedAttempts - freeAttempts, 7); // 30 s · 2^7 > 1 h
  return Duration(seconds: min(30 << doublings, 3600));
}

/// Hashes PINs with PBKDF2-HMAC-SHA256 into a self-describing record:
/// `pbkdf2-sha256$<iterations>$<saltB64>$<hashB64>`.
// ponytail: pure-Dart PBKDF2 at 210k iterations (~0.5–2 s in an isolate).
// Argon2id / 600k via cryptography_flutter when native speed is available.
class PinHasher {
  const PinHasher({this.iterations = 210000});

  /// Lower only in tests.
  final int iterations;

  static const _scheme = 'pbkdf2-sha256';
  static const _maxIterations = 10000000;

  Future<String> hash(String pin) async {
    final rnd = Random.secure();
    final salt = List<int>.generate(16, (_) => rnd.nextInt(256));
    final n = iterations;
    final digest = await Isolate.run(() => _derive(pin, salt, n));
    return [_scheme, '$n', base64Encode(salt), base64Encode(digest)].join(r'$');
  }

  /// False for a wrong PIN or a malformed record.
  Future<bool> verify(String pin, String record) async {
    final parts = record.split(r'$');
    if (parts.length != 4 || parts[0] != _scheme) return false;
    final n = int.tryParse(parts[1]);
    if (n == null || n < 1 || n > _maxIterations) return false;
    final List<int> salt, expected;
    try {
      salt = base64Decode(parts[2]);
      expected = base64Decode(parts[3]);
    } on FormatException {
      return false;
    }
    final actual = await Isolate.run(() => _derive(pin, salt, n));
    return _constantTimeEquals(actual, expected);
  }
}

Future<List<int>> _derive(String pin, List<int> salt, int iterations) async {
  final kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);
  final key = await kdf.deriveKey(secretKey: SecretKey(utf8.encode(pin)), nonce: salt);
  return key.extractBytes();
}

bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
