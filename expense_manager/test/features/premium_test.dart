import 'package:expense_manager/features/premium/application/premium_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

PurchaseDetails _purchase(String id, PurchaseStatus status) => PurchaseDetails(
      productID: id,
      verificationData: PurchaseVerificationData(localVerificationData: '', serverVerificationData: '', source: 'test'),
      transactionDate: null,
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
}
