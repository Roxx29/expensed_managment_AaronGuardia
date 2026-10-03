import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

/// Google Play product ids. Create them with these exact ids in Play Console:
/// two subscriptions (each with a 7-day free-trial offer) and one one-time
/// product for lifetime access.
const monthlyProductId = 'monchi_monthly';
const yearlyProductId = 'monchi_yearly';
const lifetimeProductId = 'monchi_lifetime';
const premiumProductIds = {monthlyProductId, yearlyProductId, lifetimeProductId};

/// What the free plan allows. Premium removes every limit.
abstract final class FreeLimits {
  static const categoryBudgets = 2;
  static const savingsGoals = 1;
  static const recurringItems = 3; // subscriptions + recurring expenses
  static const customCategories = 5;
}

/// True when [p] is a paid (or restored) Monchi Premium purchase.
bool grantsPremium(PurchaseDetails p) =>
    premiumProductIds.contains(p.productID) &&
    (p.status == PurchaseStatus.purchased || p.status == PurchaseStatus.restored);

// Kept in secure storage, not SQLite, so a backup file can't carry Premium to
// another install. It is only a cache: Google Play is asked on every launch.
const _cacheKey = 'premium.active';
const _storage = FlutterSecureStorage(aOptions: AndroidOptions());

/// Whether Monchi Premium is unlocked. Always false off Android (tests, iOS).
// ponytail: client-side check only, no receipt verification server; add Play
// Developer API verification when the app gets a backend.
final premiumProvider = NotifierProvider<PremiumNotifier, bool>(PremiumNotifier.new);

class PremiumNotifier extends Notifier<bool> {
  StreamSubscription<List<PurchaseDetails>>? _purchases;
  bool _boughtNow = false; // a purchase seen this session wins over a slower query

  @override
  bool build() {
    ref.onDispose(() => _purchases?.cancel());
    if (Platform.isAndroid) unawaited(_start());
    return false;
  }

  Future<void> _start() async {
    try {
      if (await _storage.read(key: _cacheKey) == '1' && ref.mounted) state = true;
      _purchases = InAppPurchase.instance.purchaseStream.listen(_onPurchases, onError: (Object _) {});
      await refresh();
    } on Object {
      // No Play Store (sideloaded APK, emulator without Play): keep the cache.
    }
  }

  /// Asks Google Play which purchases are active. Also "Restore purchases".
  // ponytail: checked on launch only; a renewal or cancellation mid-session is
  // picked up next launch. Re-check on app resume if that matters.
  Future<void> refresh() async {
    try {
      if (!Platform.isAndroid || !await InAppPurchase.instance.isAvailable()) return;
      final android = InAppPurchase.instance.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      final response = await android.queryPastPurchases();
      if (response.error != null) return; // offline: keep the cached value
      await _onPurchases(response.pastPurchases);
      await _save(_boughtNow || response.pastPurchases.any(grantsPremium));
    } on Object {
      // Play disconnected: keep the cached value.
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (!premiumProductIds.contains(p.productID)) continue;
      if (grantsPremium(p)) {
        _boughtNow = true;
        await _save(true);
      }
      // Google refunds purchases that are not acknowledged within 3 days.
      if (p.pendingCompletePurchase && p.status != PurchaseStatus.pending) {
        await InAppPurchase.instance.completePurchase(p);
      }
    }
  }

  Future<void> _save(bool active) async {
    if (ref.mounted) state = active;
    await _storage.write(key: _cacheKey, value: active ? '1' : '0');
  }

  /// Opens Google Play's purchase sheet. The result arrives on the purchase
  /// stream; returns false if the sheet could not open.
  Future<bool> buy(ProductDetails product) async {
    try {
      return await InAppPurchase.instance.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: product));
    } on Object {
      return false;
    }
  }
}

/// The three plans in display order (monthly, yearly, lifetime). Empty when
/// Google Play is unavailable or the products don't exist yet.
final premiumPlansProvider = FutureProvider.autoDispose<List<ProductDetails>>((ref) async {
  if (!Platform.isAndroid || !await InAppPurchase.instance.isAvailable()) return const [];
  final response = await InAppPurchase.instance.queryProductDetails(premiumProductIds);
  // Play returns one entry per subscription offer; keep the free trial when
  // the user is still eligible for it, else the base plan.
  final byId = <String, ProductDetails>{};
  for (final p in response.productDetails) {
    final current = byId[p.id];
    if (current == null || (hasFreeTrial(p) && !hasFreeTrial(current))) byId[p.id] = p;
  }
  return [for (final id in [monthlyProductId, yearlyProductId, lifetimeProductId]) ?byId[id]];
});

/// True when this subscription offer starts with a free period.
bool hasFreeTrial(ProductDetails p) =>
    p is GooglePlayProductDetails &&
    p.subscriptionIndex != null &&
    p.productDetails.subscriptionOfferDetails![p.subscriptionIndex!].pricingPhases.first.priceAmountMicros == 0;

/// The recurring price ("$1.99"), not the trial's "Free".
String regularPrice(ProductDetails p) => p is GooglePlayProductDetails && p.subscriptionIndex != null
    ? p.productDetails.subscriptionOfferDetails![p.subscriptionIndex!].pricingPhases.last.formattedPrice
    : p.price;
