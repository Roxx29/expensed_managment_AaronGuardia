import 'package:expense_manager/domain/wallets/invite_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const id = 'AbCdEfGhIjKlMnOpQrSt_-';
  const key = 'k123456789012345678901234567890123456789-_x';

  test('round trip, also inside a shared message', () {
    expect(id, hasLength(22));
    expect(key, hasLength(43));
    final code = inviteCode(id, key);
    expect(parseInviteCode(code), (inviteId: id, walletKey: key));
    expect(parseInviteCode('Únete a mi cartera en Monchi: $code ¡gracias!'), (inviteId: id, walletKey: key));
  });

  test('the invite link carries the code after # and parses back', () {
    final link = inviteLink(inviteCode(id, key));
    expect(link, startsWith('https://monchiadmin.nubiksoft.com/join#'));
    expect(Uri.parse(link).fragment, inviteCode(id, key));
    expect(parseInviteCode(link), (inviteId: id, walletKey: key));
  });

  test('rejects text without a code', () {
    expect(parseInviteCode(''), isNull);
    expect(parseInviteCode('hola.mundo'), isNull);
    expect(parseInviteCode('$id.short'), isNull);
  });
}
