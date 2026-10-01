// PBKDF2 runs in pure Dart: each key derivation takes a moment.
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';

import 'package:expense_manager/data/backup/backup_codec.dart';
import 'package:expense_manager/data/backup/backup_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const plain = '{"format":"expense-manager-backup","data":{"note":"café ☕"}}';
  const passphrase = 'correct horse';
  late String envelope;

  setUpAll(() async => envelope = await encryptBackup(plain, passphrase));

  Future<BackupError?> decryptError(String content, [String pass = passphrase]) async {
    try {
      await decryptBackup(content, pass);
      return null;
    } on BackupException catch (e) {
      return e.error;
    }
  }

  String edit(void Function(Map<String, dynamic> json) change) {
    final json = jsonDecode(envelope) as Map<String, dynamic>;
    change(json);
    return jsonEncode(json);
  }

  test('roundtrip, and the plain text is not visible', () async {
    expect(envelope, isNot(contains('café')));
    expect(isEncryptedBackup(envelope), isTrue);
    expect(isEncryptedBackup(plain), isFalse);
    expect(await decryptBackup(envelope, passphrase), plain);
  });

  test('fresh salt and nonce every time', () async {
    final other = await encryptBackup(plain, passphrase);
    final a = jsonDecode(envelope) as Map<String, dynamic>;
    final b = jsonDecode(other) as Map<String, dynamic>;
    expect(a['salt'], isNot(b['salt']));
    expect(a['nonce'], isNot(b['nonce']));
  });

  test('wrong passphrase', () async {
    expect(await decryptError(envelope, 'wrong horse'), BackupError.wrongPassphrase);
  });

  test('tampered ciphertext is detected', () async {
    final tampered = edit((json) {
      final ct = base64.decode(json['ct'] as String);
      ct[0] ^= 1;
      json['ct'] = base64.encode(ct);
    });
    expect(await decryptError(tampered), BackupError.wrongPassphrase);
  });

  test('malformed envelopes are rejected before any key derivation', () async {
    expect(await decryptError('not json'), BackupError.corrupted);
    expect(await decryptError('[]'), BackupError.corrupted);
    expect(await decryptError(edit((j) => j.remove('mac'))), BackupError.corrupted);
    expect(await decryptError(edit((j) => j['salt'] = '%%%')), BackupError.corrupted);
    expect(await decryptError(edit((j) => j['v'] = 2)), BackupError.corrupted);
    // A huge iteration count would freeze the app.
    expect(await decryptError(edit((j) => j['iter'] = 1000000000)), BackupError.corrupted);
    expect(await decryptError(edit((j) => j['iter'] = 1)), BackupError.corrupted);
  });

  test('short passphrases are refused', () {
    expect(() => encryptBackup(plain, 'short'), throwsArgumentError);
  });
}
