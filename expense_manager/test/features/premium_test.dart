import 'package:expense_manager/domain/premium/premium_status.dart';
import 'package:expense_manager/features/premium/application/premium_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

PurchaseDetails _purchase(String id, PurchaseStatus status, {DateTime? at}) => PurchaseDetails(
      productID: id,
      verificationData: PurchaseVerificationData(localVerificationData: '', serverVerificationData: '', source: 'test'),
      transactionDate: at?.millisecondsSinceEpoch.toString(),
      status: status,
    );

void main() {
  test('paid or restored Monchi plans unlock Premium', () {
    for (final id in premiumProductIds) {
      expect(grantsPremium(_purchase(id, PurchaseStatus.purchased)), isTrue, reason: id);
      expect(grantsPremium(_purchase(id, PurchaseStatus.restored)), isTrue, reason: id);
    }
  });

  test('pending, failed, canceled or unknown products do not', () {
    expect(grantsPremium(_purchase(monthlyProductId, PurchaseStatus.pending)), isFalse);
    expect(grantsPremium(_purchase(monthlyProductId, PurchaseStatus.error)), isFalse);
    expect(grantsPremium(_purchase(yearlyProductId, PurchaseStatus.canceled)), isFalse);
    expect(grantsPremium(_purchase('other_app_item', PurchaseStatus.purchased)), isFalse);
  });

  test('status comes from the best active purchase: lifetime first, dates from Play', () {
    final now = DateTime(2026, 10, 4);
    final monthly = _purchase(monthlyProductId, PurchaseStatus.purchased, at: DateTime(2026, 9, 15));
    final s = statusFromPurchases([monthly], now)!;
    expect(s.plan, PremiumPlan.monthly);
    expect(s.until, DateTime(2026, 10, 15));
    expect(s.renews, isTrue, reason: 'non-Play purchase details assume auto-renew');
    final lifetime = _purchase(lifetimeProductId, PurchaseStatus.restored);
    expect(statusFromPurchases([monthly, lifetime], now)!.plan, PremiumPlan.lifetime);
    expect(statusFromPurchases([_purchase(monthlyProductId, PurchaseStatus.pending)], now), isNull);
  });
}
