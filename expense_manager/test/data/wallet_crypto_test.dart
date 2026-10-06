import 'package:expense_manager/data/backup/backup_codec.dart';
import 'package:expense_manager/data/backup/backup_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<BackupError?> error(Future<String> Function() f) async {
    try {
      await f();
      return null;
    } on BackupException catch (e) {
      return e.error;
    }
  }

  test('wallet data round-trips only with its own key', () async {
    final key = newWalletSecret();
    expect(key, hasLength(43));
    expect(key, isNot(contains('=')));
    final sealed = await encryptWithSecret('hola ☕', key);
    expect(sealed, isNot(contains('hola')));
    expect(await decryptWithSecret(sealed, key), 'hola ☕');
    expect(await error(() => decryptWithSecret(sealed, newWalletSecret())), BackupError.wrongPassphrase);
    expect(await error(() => decryptWithSecret('nope', key)), BackupError.corrupted);
    expect(await error(() => decryptWithSecret(sealed, 'short')), BackupError.corrupted);
  });
}
