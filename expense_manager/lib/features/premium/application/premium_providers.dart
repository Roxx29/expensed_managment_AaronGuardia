import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import '../../../domain/premium/premium_status.dart';
import 'gift_providers.dart';

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

/// What the user has (plan, end or renewal date), or null on the free plan.
/// Always null off Android (tests, iOS).
final premiumStatusProvider = Provider<PremiumStatus?>((ref) {
  final gift = ref.watch(giftPremiumProvider).value;
  // Google Play is what the user pays for and manages, so it is shown first.
  return ref.watch(playPremiumProvider) ?? (gift == null ? null : PremiumStatus.gift(gift));
});

/// Whether Monchi Premium is unlocked: bought on Google Play or given from the
/// admin panel.
final premiumProvider = Provider<bool>((ref) => ref.watch(premiumStatusProvider) != null);

/// Bought on Google Play (null = nothing active).
// ponytail: client-side check only, no receipt verification server; add Play
// Developer API verification when the app gets a backend.
final playPremiumProvider = NotifierProvider<PremiumNotifier, PremiumStatus?>(PremiumNotifier.new);

/// The plan a Google Play product id unlocks.
PremiumPlan planOf(String productId) => switch (productId) {
      monthlyProductId => PremiumPlan.monthly,
      yearlyProductId => PremiumPlan.yearly,
      lifetimeProductId => PremiumPlan.lifetime,
      _ => PremiumPlan.unknown,
    };

/// Status of the best active purchase (lifetime first); null when none.
PremiumStatus? statusFromPurchases(Iterable<PurchaseDetails> purchases, DateTime now) {
  final statuses = [
    for (final p in purchases)
      if (grantsPremium(p))
        PremiumStatus.play(
          plan: planOf(p.productID),
          purchasedAt: switch (int.tryParse(p.transactionDate ?? '')) {
            final ms? => DateTime.fromMillisecondsSinceEpoch(ms),
            null => null,
          },
          autoRenewing: p is GooglePlayPurchaseDetails ? p.billingClientPurchase.isAutoRenewing : true,
          now: now,
        ),
  ];
  if (statuses.isEmpty) return null;
  return statuses.firstWhere((s) => s.plan == PremiumPlan.lifetime, orElse: () => statuses.first);
}

class PremiumNotifier extends Notifier<PremiumStatus?> {
  StreamSubscription<List<PurchaseDetails>>? _purchases;
  AppLifecycleListener? _lifecycle;
  PremiumStatus? _boughtNow; // a purchase seen this session, if Play's query lags

  @override
  PremiumStatus? build() {
    ref.onDispose(() {
      _purchases?.cancel();
      _lifecycle?.dispose();
    });
    if (Platform.isAndroid) unawaited(_start());
    return null;
  }

  Future<void> _start() async {
    try {
      final cached = PremiumStatus.fromCache(await _storage.read(key: _cacheKey), now: DateTime.now());
      if (cached != null && ref.mounted) state = cached;
    } on Object {
      // Unreadable cache (e.g. Keystore key lost): Google Play answers below.
    }
    try {
      _purchases = InAppPurchase.instance.purchaseStream.listen(_onPurchases, onError: (Object _) {});
      // Renewals and cancellations made in Google Play while Monchi was in the background.
      _lifecycle = AppLifecycleListener(onResume: () => unawaited(refresh()));
      await refresh();
    } on Object {
      // No Play Store (sideloaded APK, emulator without Play): keep the cache.
    }
  }

  /// Asks Google Play which purchases are active. Also "Restore purchases".
  /// Runs on launch and whenever the app comes back to the foreground.
  Future<void> refresh() async {
    try {
      if (!Platform.isAndroid || !await InAppPurchase.instance.isAvailable()) return;
      final android = InAppPurchase.instance.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      final response = await android.queryPastPurchases();
      if (response.error != null) return; // offline: keep the cached value
      await _acknowledge(response.pastPurchases);
      await _save(statusFromPurchases(response.pastPurchases, DateTime.now()) ?? _boughtNow);
    } on Object {
      // Play disconnected: keep the cached value.
    }
  }

  /// Purchases made from the purchase sheet (the stream).
  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    final bought = statusFromPurchases(purchases, DateTime.now());
    if (bought != null) {
      _boughtNow = bought;
      await _save(bought);
    }
    await _acknowledge(purchases);
  }

  /// Google refunds purchases that are not acknowledged within 3 days.
  Future<void> _acknowledge(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (premiumProductIds.contains(p.productID) && p.pendingCompletePurchase && p.status != PurchaseStatus.pending) {
        await InAppPurchase.instance.completePurchase(p);
      }
    }
  }

  Future<void> _save(PremiumStatus? status) async {
    if (ref.mounted) state = status;
    await _storage.write(key: _cacheKey, value: status?.toCache() ?? '0');
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
