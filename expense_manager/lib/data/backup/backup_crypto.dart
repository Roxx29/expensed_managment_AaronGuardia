import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'backup_codec.dart';

/// Password-encrypted backup files: AES-256-GCM with a PBKDF2-SHA256 key.
///
/// The envelope is JSON:
/// `{"format","v","kdf","iter","salt","nonce","ct","mac"}` (binary as base64).

const encryptedBackupFormat = 'expense-manager-encrypted';
const minPassphraseLength = 8;

// ponytail: 210k PBKDF2 iterations (OWASP asks 600k for PBKDF2-SHA256) because
// the pure-Dart KDF is slow on phones; it runs on a background isolate. Upgrade
// path: Argon2id or a native KDF (cryptography_flutter), bumping `v`.
const _iterations = 210000;

/// Accepted `iter` range on decrypt, so a hostile file can't hang the app.
const _minIterations = 100000;
const _maxIterations = 2000000;

/// True when [content] looks like an encrypted backup envelope (cheap check:
/// only the start of the file is inspected; [decryptBackup] validates fully).
bool isEncryptedBackup(String content) => RegExp('"format"\\s*:\\s*"$encryptedBackupFormat"')
    .hasMatch(content.substring(0, min(content.length, 256)));

/// Encrypts a plain backup [json] with [passphrase]. Throws [ArgumentError]
/// when the passphrase is shorter than [minPassphraseLength].
Future<String> encryptBackup(String json, String passphrase) {
  if (passphrase.length < minPassphraseLength) {
    throw ArgumentError('passphrase must have at least $minPassphraseLength characters');
  }
  final salt = _randomBytes(16);
  final nonce = _randomBytes(12);
  return Isolate.run(() async {
    final key = await _deriveKey(passphrase, salt, _iterations);
    final box = await AesGcm.with256bits().encrypt(utf8.encode(json), secretKey: key, nonce: nonce);
    return jsonEncode({
      'format': encryptedBackupFormat,
      'v': 1,
      'kdf': 'pbkdf2-sha256',
      'iter': _iterations,
      'salt': base64.encode(salt),
      'nonce': base64.encode(box.nonce),
      'ct': base64.encode(box.cipherText),
      'mac': base64.encode(box.mac.bytes),
    });
  });
}

/// Decrypts an envelope made by [encryptBackup] back to the plain backup JSON.
/// Throws [BackupException] with [BackupError.wrongPassphrase] when the
/// passphrase is wrong or the ciphertext was modified (GCM cannot tell the
/// two apart), and [BackupError.corrupted] when the envelope is malformed.
Future<String> decryptBackup(String envelope, String passphrase) =>
    Isolate.run(() => _decrypt(envelope, passphrase));

Future<String> _decrypt(String envelope, String passphrase) async {
  final int iterations;
  final SecretBox box;
  final List<int> salt;
  try {
    final root = jsonDecode(envelope) as Map<String, Object?>;
    if (root['format'] != encryptedBackupFormat || root['v'] != 1 || root['kdf'] != 'pbkdf2-sha256') {
      throw const FormatException();
    }
    iterations = root['iter']! as int;
    salt = base64.decode(root['salt']! as String);
    final nonce = base64.decode(root['nonce']! as String);
    final mac = base64.decode(root['mac']! as String);
    if (iterations < _minIterations ||
        iterations > _maxIterations ||
        salt.length != 16 ||
        nonce.length != 12 ||
        mac.length != 16) {
      throw const FormatException();
    }
    box = SecretBox(base64.decode(root['ct']! as String), nonce: nonce, mac: Mac(mac));
  } on Object {
    throw const BackupException(BackupError.corrupted);
  }
  final key = await _deriveKey(passphrase, salt, iterations);
  final List<int> clear;
  try {
    clear = await AesGcm.with256bits().decrypt(box, secretKey: key);
  } on SecretBoxAuthenticationError {
    throw const BackupException(BackupError.wrongPassphrase);
  }
  try {
    return utf8.decode(clear);
  } on FormatException {
    throw const BackupException(BackupError.corrupted);
  }
}

Future<SecretKey> _deriveKey(String passphrase, List<int> salt, int iterations) =>
    Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256)
        .deriveKeyFromPassword(password: passphrase, nonce: salt);

List<int> _randomBytes(int length) {
  final random = Random.secure();
  return List<int>.generate(length, (_) => random.nextInt(256));
}

/// Envelope of data encrypted with a shared wallet's random key (no KDF:
/// the key is already 256 random bits, so this stays fast on every sync).
const walletCipherFormat = 'monchi-wallet';

/// A new random wallet key, base64url without padding (43 characters).
String newWalletSecret() => base64Url.encode(_randomBytes(32)).replaceAll('=', '');

List<int> _walletKey(String secret) {
  final key = base64Url.decode(base64Url.normalize(secret));
  if (key.length != 32) throw const FormatException('wallet key');
  return key;
}

/// Encrypts [text] with the wallet key [secret] (AES-256-GCM).
Future<String> encryptWithSecret(String text, String secret) {
  final key = _walletKey(secret);
  final nonce = _randomBytes(12);
  return Isolate.run(() async {
    final box = await AesGcm.with256bits().encrypt(utf8.encode(text), secretKey: SecretKey(key), nonce: nonce);
    return jsonEncode({
      'format': walletCipherFormat,
      'v': 1,
      'nonce': base64.encode(box.nonce),
      'ct': base64.encode(box.cipherText),
      'mac': base64.encode(box.mac.bytes),
    });
  });
}

/// Reverses [encryptWithSecret]. [BackupError.wrongPassphrase] for another
/// key or modified data, [BackupError.corrupted] for a malformed envelope.
Future<String> decryptWithSecret(String envelope, String secret) => Isolate.run(() async {
      final SecretBox box;
      final List<int> key;
      try {
        key = _walletKey(secret);
        final root = jsonDecode(envelope) as Map<String, Object?>;
        if (root['format'] != walletCipherFormat || root['v'] != 1) throw const FormatException();
        final nonce = base64.decode(root['nonce']! as String);
        final mac = base64.decode(root['mac']! as String);
        if (nonce.length != 12 || mac.length != 16) throw const FormatException();
        box = SecretBox(base64.decode(root['ct']! as String), nonce: nonce, mac: Mac(mac));
      } on Object {
        throw const BackupException(BackupError.corrupted);
      }
      final List<int> clear;
      try {
        clear = await AesGcm.with256bits().decrypt(box, secretKey: SecretKey(key));
      } on SecretBoxAuthenticationError {
        throw const BackupException(BackupError.wrongPassphrase);
      }
      try {
        return utf8.decode(clear);
      } on FormatException {
        throw const BackupException(BackupError.corrupted);
      }
    });
