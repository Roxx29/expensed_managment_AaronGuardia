import 'package:expense_manager/domain/premium/gift_premium.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 4, 12);

  test('no gifts, revoked or expired gifts give nothing', () {
    expect(giftPremiumActive(const [], blocked: false, now: now), isFalse);
    expect(giftPremiumActive([const Gift(revoked: true)], blocked: false, now: now), isFalse);
    expect(giftPremiumActive([Gift(until: now)], blocked: false, now: now), isFalse);
  });

  test('a forever or future gift unlocks Premium unless blocked', () {
    expect(giftPremiumActive([const Gift()], blocked: false, now: now), isTrue);
    expect(giftPremiumActive([Gift(until: now.add(const Duration(days: 1)))], blocked: false, now: now), isTrue);
    expect(giftPremiumActive([const Gift(revoked: true), const Gift()], blocked: false, now: now), isTrue);
    expect(giftPremiumActive([const Gift()], blocked: true, now: now), isFalse);
  });

  test('a code lasts its days from redemption; no days = forever', () {
    final at = DateTime.utc(2026, 10, 1);
    expect(Gift.fromCode(redeemedAt: at, days: 30).until, DateTime.utc(2026, 10, 31));
    expect(Gift.fromCode(redeemedAt: at, days: null).until, isNull);
    expect(Gift.fromCode(redeemedAt: null, days: 30).until, isNotNull, reason: 'pending server time counts as now');
  });

  test('codes are normalised to upper case without spaces', () {
    expect(normalizeCode('  monchi-ab12 '), 'MONCHI-AB12');
    expect(isValidCode('MONCHI-AB12'), isTrue);
    expect(isValidCode('ab'), isFalse);
    expect(isValidCode('A/B/C/D'), isFalse);
  });
}
