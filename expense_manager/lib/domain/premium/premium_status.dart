import '../entities/enums.dart';
import '../finance/recurrence.dart';
import 'gift_premium.dart';

/// How Premium was unlocked. [unknown] = cached by an older build.
enum PremiumPlan { monthly, yearly, lifetime, gift, unknown }

/// What the user has: which plan, until when, and whether it renews.
class PremiumStatus {
  const PremiumStatus({required this.plan, this.purchasedAt, this.until, this.renews = false});

  /// A Google Play purchase. Subscriptions end at the next period boundary
  /// counted from [purchasedAt]; lifetime never ends.
  // ponytail: Play's client API has no expiry date, so the end is estimated
  // from the purchase day (a free trial or a grace period shifts it a few
  // days); read expiryTime from the Play Developer API once there is a server.
  factory PremiumStatus.play({
    required PremiumPlan plan,
    required DateTime? purchasedAt,
    required bool autoRenewing,
    required DateTime now,
  }) {
    final rule = switch (plan) {
      PremiumPlan.monthly => const RecurrenceRule(Frequency.monthly),
      PremiumPlan.yearly => const RecurrenceRule(Frequency.yearly),
      _ => null,
    };
    return PremiumStatus(
      plan: plan,
      purchasedAt: purchasedAt,
      until: rule == null || purchasedAt == null
          ? null
          : rule.nextOccurrence(purchasedAt, onOrAfter: DateTime(now.year, now.month, now.day + 1)),
      renews: rule != null && autoRenewing,
    );
  }

  /// Premium given from the admin panel (e-mail gift or promo code).
  factory PremiumStatus.gift(Gift gift) => PremiumStatus(plan: PremiumPlan.gift, until: gift.until);

  final PremiumPlan plan;
  final DateTime? purchasedAt;

  /// Next renewal (when [renews]) or the day Premium ends. Null = never ends.
  final DateTime? until;
  final bool renews;

  /// Calendar days until [until]; null when it never ends.
  int? daysLeft(DateTime now) => until == null
      ? null
      : DateTime.utc(until!.year, until!.month, until!.day).difference(DateTime.utc(now.year, now.month, now.day)).inDays;

  /// Ends within a week and will not renew: worth a warning.
  bool endsSoon(DateTime now) => !renews && (daysLeft(now) ?? 99) <= 7;

  /// Secure-storage cache: `plan|purchaseMillis|renews`.
  String toCache() => '${plan.name}|${purchasedAt?.millisecondsSinceEpoch ?? ''}|${renews ? 1 : 0}';

  /// Null = no Premium. `'1'` is the old cache format (plan unknown).
  static PremiumStatus? fromCache(String? value, {required DateTime now}) {
    if (value == null || value == '0' || value.isEmpty) return null;
    final parts = value.split('|');
    if (parts.length != 3) return const PremiumStatus(plan: PremiumPlan.unknown);
    final plan = PremiumPlan.values.asNameMap()[parts[0]];
    if (plan == null || plan == PremiumPlan.gift) return null; // not written by toCache
    final ms = int.tryParse(parts[1]);
    return PremiumStatus.play(
      plan: plan,
      purchasedAt: ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms),
      autoRenewing: parts[2] == '1',
      now: now,
    );
  }
}
