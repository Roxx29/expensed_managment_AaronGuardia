/// Immutable domain models. Independent of Flutter and of the database.
library;

import '../../core/money/currency.dart';
import '../../core/money/money.dart';
import '../../core/time/year_month.dart';
import '../finance/recurrence.dart';
import 'enums.dart';

export 'enums.dart';

class FinanceCategory {
  const FinanceCategory({
    required this.id,
    required this.name,
    required this.iconKey,
    required this.color,
    required this.kind,
    this.isDefault = false,
    this.sortOrder = 0,
    this.archived = false,
  });

  final String id;
  final String name;

  /// Key into the app icon registry (keeps Flutter out of the domain).
  final String iconKey;

  /// ARGB color value.
  final int color;
  final CategoryKind kind;
  final bool isDefault;
  final int sortOrder;
  final bool archived;

  bool appliesTo(TransactionType type) => switch (kind) {
        CategoryKind.both => true,
        CategoryKind.expense => type == TransactionType.expense,
        CategoryKind.income => type == TransactionType.income,
      };
}

class PaymentMethod {
  const PaymentMethod({
    required this.id,
    required this.name,
    required this.type,
    this.isDefault = false,
    this.archived = false,
  });

  final String id;
  final String name;
  final PaymentMethodType type;
  final bool isDefault;
  final bool archived;
}

/// Named `FinanceTransaction` to avoid clashing with database transactions.
class FinanceTransaction {
  const FinanceTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.occurredAt,
    this.description = '',
    this.categoryId,
    this.paymentMethodId,
    this.recurringItemId,
    this.savingsGoalId,
    this.source,
    this.notes,
    this.project,
    this.walletId,
    this.createdBy,
  });

  final String id;
  final TransactionType type;

  /// Always positive; [type] carries the direction.
  final Money amount;
  final DateTime occurredAt;
  final String description;
  final String? categoryId;
  final String? paymentMethodId;

  /// Set when generated from a recurring expense or subscription.
  final String? recurringItemId;
  final String? savingsGoalId;

  /// Income source (e.g. "Salary").
  final String? source;
  final String? notes;

  /// Project or client (freelancers); null = personal.
  final String? project;

  /// Shared wallet this entry belongs to; null = the user's own money.
  final String? walletId;

  /// Account (Firebase uid) that recorded it, shown in shared wallets.
  final String? createdBy;
}

/// A shared wallet (Cartera). [secret] is the base64url AES key that
/// encrypts its cloud copy; it only travels inside invite codes and the
/// user's own encrypted backup.
class Wallet {
  const Wallet({
    required this.id,
    required this.name,
    required this.kind,
    required this.secret,
    this.ownerUid,
  });

  final String id;
  final String name;
  final WalletKind kind;
  final String secret;
  final String? ownerUid;
}

/// A monthly budget. `categoryId == null` is the global budget.
/// Valid from [startMonth] until [endMonth] (inclusive, null = open-ended).
class Budget {
  const Budget({
    required this.id,
    required this.amount,
    required this.startMonth,
    this.categoryId,
    this.endMonth,
  });

  final String id;
  final String? categoryId;
  final Money amount;
  final YearMonth startMonth;
  final YearMonth? endMonth;

  bool get isGlobal => categoryId == null;

  bool appliesTo(YearMonth month) =>
      startMonth.compareTo(month) <= 0 &&
      (endMonth == null || endMonth!.compareTo(month) >= 0);
}

/// A recurring expense (bill) or a subscription.
class RecurringItem {
  const RecurringItem({
    required this.id,
    required this.kind,
    required this.name,
    required this.amount,
    required this.rule,
    required this.anchorDate,
    this.endDate,
    this.postedFrom,
    this.categoryId,
    this.paymentMethodId,
    this.isActive = true,
    this.notes,
  });

  final String id;
  final RecurringKind kind;
  final String name;
  final Money amount;
  final RecurrenceRule rule;

  /// First billing date; later dates are derived from [rule].
  final DateTime anchorDate;
  final DateTime? endDate;

  /// Occurrences before this date are not auto-posted (see RecurringPoster).
  final DateTime? postedFrom;
  final String? categoryId;
  final String? paymentMethodId;
  final bool isActive;
  final String? notes;

  RecurringItem copyWith({bool? isActive, DateTime? postedFrom}) => RecurringItem(
        id: id,
        kind: kind,
        name: name,
        amount: amount,
        rule: rule,
        anchorDate: anchorDate,
        endDate: endDate,
        postedFrom: postedFrom ?? this.postedFrom,
        categoryId: categoryId,
        paymentMethodId: paymentMethodId,
        isActive: isActive ?? this.isActive,
        notes: notes,
      );

  Money get monthlyCost => rule.monthlyCost(amount);
  Money get yearlyCost => rule.yearlyCost(amount);

  DateTime? nextDueDate(DateTime from) => isActive
      ? rule.nextOccurrence(anchorDate, onOrAfter: from, endDate: endDate)
      : null;
}

class SavingsGoal {
  const SavingsGoal({
    required this.id,
    required this.name,
    required this.target,
    this.targetDate,
    this.archived = false,
  });

  final String id;
  final String name;
  final Money target;
  final DateTime? targetDate;
  final bool archived;
}

class Profile {
  const Profile({
    required this.id,
    required this.currency,
    this.name = '',
    this.email,
    this.avatarPath,
    this.countryCode,
  });

  final String id;
  final String name;
  final String? email;
  final String? avatarPath;
  final String? countryCode;
  final Currency currency;

  Profile copyWith({
    String? name,
    String? email,
    String? avatarPath,
    String? countryCode,
    Currency? currency,
  }) =>
      Profile(
        id: id,
        currency: currency ?? this.currency,
        name: name ?? this.name,
        email: email ?? this.email,
        avatarPath: avatarPath ?? this.avatarPath,
        countryCode: countryCode ?? this.countryCode,
      );
}
