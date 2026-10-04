import 'package:expense_manager/domain/premium/gift_premium.dart';
import 'package:expense_manager/domain/premium/premium_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 4, 12);

  test('monthly subscription: next renewal is the next monthly boundary after today', () {
    final s = PremiumStatus.play(plan: PremiumPlan.monthly, purchasedAt: DateTime(2026, 8, 31), autoRenewing: true, now: now);
    expect(s.until, DateTime(2026, 10, 31));
    expect(s.renews, isTrue);
    expect(s.daysLeft(now), 27);
  });

  test('a subscription bought today renews in one period, not today', () {
    final s = PremiumStatus.play(plan: PremiumPlan.yearly, purchasedAt: now, autoRenewing: true, now: now);
    expect(s.until, DateTime(2027, 10, 4));
  });

  test('a canceled subscription keeps the same end date but does not renew', () {
    final s = PremiumStatus.play(plan: PremiumPlan.monthly, purchasedAt: DateTime(2026, 9, 20), autoRenewing: false, now: now);
    expect(s.until, DateTime(2026, 10, 20));
    expect(s.renews, isFalse);
    expect(s.endsSoon(now), isFalse);
    expect(s.endsSoon(DateTime(2026, 10, 15)), isTrue, reason: '5 days left');
  });

  test('lifetime and unknown purchase dates never show an end', () {
    expect(PremiumStatus.play(plan: PremiumPlan.lifetime, purchasedAt: DateTime(2026), autoRenewing: false, now: now).until, isNull);
    expect(PremiumStatus.play(plan: PremiumPlan.monthly, purchasedAt: null, autoRenewing: true, now: now).until, isNull);
    expect(const PremiumStatus(plan: PremiumPlan.lifetime).daysLeft(now), isNull);
  });

  test('cache round-trip keeps plan, purchase time and renewal', () {
    final s = PremiumStatus.play(plan: PremiumPlan.yearly, purchasedAt: DateTime(2026, 1, 2), autoRenewing: false, now: now);
    final back = PremiumStatus.fromCache(s.toCache(), now: now)!;
    expect(back.plan, PremiumPlan.yearly);
    expect(back.until, s.until);
    expect(back.renews, isFalse);
    expect(PremiumStatus.fromCache('0', now: now), isNull);
    expect(PremiumStatus.fromCache(null, now: now), isNull);
    expect(PremiumStatus.fromCache('1', now: now)?.plan, PremiumPlan.unknown, reason: 'old cache format');
    expect(PremiumStatus.fromCache('junk||0', now: now), isNull);
  });

  test('best gift: forever wins, else the latest end; expired, revoked or blocked give none', () {
    final soon = Gift(until: now.add(const Duration(days: 3)));
    final later = Gift(until: now.add(const Duration(days: 30)));
    expect(bestGift([soon, later], blocked: false, now: now), same(later));
    expect(bestGift([later, const Gift()], blocked: false, now: now)?.until, isNull);
    expect(bestGift([Gift(until: now), const Gift(revoked: true)], blocked: false, now: now), isNull);
    expect(bestGift([later], blocked: true, now: now), isNull);
  });

  test('gift status shows its end date and never renews', () {
    final gift = PremiumStatus.gift(Gift(until: DateTime(2026, 10, 9)));
    expect(gift.plan, PremiumPlan.gift);
    expect(gift.renews, isFalse);
    expect(gift.endsSoon(now), isTrue);
  });
}
