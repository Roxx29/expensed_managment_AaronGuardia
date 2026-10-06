import '../../core/money/money.dart';
import '../entities/entities.dart';

enum TransactionSort { newest, oldest, highest, lowest }

/// Search/filter/sort criteria for the transaction history. Immutable.
class TransactionFilter {
  const TransactionFilter({
    this.query = '',
    this.types = const {},
    this.categoryId,
    this.from,
    this.toExclusive,
    this.minAmount,
    this.maxAmount,
    this.sort = TransactionSort.newest,
  });

  final String query;

  /// Empty = all types.
  final Set<TransactionType> types;
  final String? categoryId;
  final DateTime? from;
  final DateTime? toExclusive;
  final Money? minAmount;
  final Money? maxAmount;
  final TransactionSort sort;

  bool get isActive =>
      query.isNotEmpty ||
      types.isNotEmpty ||
      categoryId != null ||
      from != null ||
      toExclusive != null ||
      minAmount != null ||
      maxAmount != null;

  // Explicit "clear" flags because null means "keep" in a plain copyWith.
  TransactionFilter copyWith({
    String? query,
    Set<TransactionType>? types,
    String? categoryId,
    bool clearCategory = false,
    DateTime? from,
    DateTime? toExclusive,
    bool clearDates = false,
    Money? minAmount,
    Money? maxAmount,
    bool clearAmounts = false,
    TransactionSort? sort,
  }) =>
      TransactionFilter(
        query: query ?? this.query,
        types: types ?? this.types,
        categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
        from: clearDates ? null : (from ?? this.from),
        toExclusive: clearDates ? null : (toExclusive ?? this.toExclusive),
        minAmount: clearAmounts ? null : (minAmount ?? this.minAmount),
        maxAmount: clearAmounts ? null : (maxAmount ?? this.maxAmount),
        sort: sort ?? this.sort,
      );

  /// [categoryNames] lets the search match category names too.
  List<FinanceTransaction> apply(
    List<FinanceTransaction> transactions, {
    Map<String, String> categoryNames = const {},
  }) {
    final q = query.trim().toLowerCase();
    bool matches(FinanceTransaction t) {
      if (types.isNotEmpty && !types.contains(t.type)) return false;
      if (categoryId != null && t.categoryId != categoryId) return false;
      if (from != null && t.occurredAt.isBefore(from!)) return false;
      if (toExclusive != null && !t.occurredAt.isBefore(toExclusive!)) return false;
      // Amount bounds compare minor units; other currencies never match.
      if (minAmount != null &&
          (t.amount.currency != minAmount!.currency || t.amount < minAmount!)) {
        return false;
      }
      if (maxAmount != null &&
          (t.amount.currency != maxAmount!.currency || t.amount > maxAmount!)) {
        return false;
      }
      if (q.isEmpty) return true;
      return [t.description, t.notes, t.source, t.project, categoryNames[t.categoryId]]
          .any((field) => field != null && field.toLowerCase().contains(q));
    }

    final result = transactions.where(matches).toList();
    int byDate(FinanceTransaction a, FinanceTransaction b) =>
        a.occurredAt.compareTo(b.occurredAt);
    int byAmount(FinanceTransaction a, FinanceTransaction b) =>
        a.amount.minor.compareTo(b.amount.minor);
    final Comparator<FinanceTransaction> compare = switch (sort) {
      TransactionSort.newest => (a, b) => byDate(b, a),
      TransactionSort.oldest => byDate,
      TransactionSort.highest => (a, b) => byAmount(b, a),
      TransactionSort.lowest => byAmount,
    };
    return result..sort(compare);
  }
}
