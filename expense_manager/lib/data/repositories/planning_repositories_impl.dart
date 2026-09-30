import 'package:drift/drift.dart';

import '../../core/money/currency.dart';
import '../../core/money/money.dart';
import '../../core/time/year_month.dart';
import '../../core/utils/ids.dart';
import '../../domain/entities/entities.dart';
import '../../domain/finance/recurrence.dart';
import '../../domain/repositories/repositories.dart';
import '../database/app_database.dart';

class DriftBudgetRepository implements BudgetRepository {
  DriftBudgetRepository(this._db);

  final AppDatabase _db;

  $BudgetsTable get _b => _db.budgets;

  Expression<bool> _activeIn(YearMonth month) =>
      _b.deletedAt.isNull() &
      _b.startMonth.isSmallerOrEqualValue(month.key) &
      (_b.endMonth.isNull() | _b.endMonth.isBiggerOrEqualValue(month.key));

  Expression<bool> _forCategory(String? categoryId) =>
      categoryId == null ? _b.categoryId.isNull() : _b.categoryId.equals(categoryId);

  @override
  Stream<List<Budget>> watchForMonth(YearMonth month) =>
      (_db.select(_b)..where((_) => _activeIn(month))).watch().map((rows) => rows
          .map((r) => Budget(
                id: r.id,
                categoryId: r.categoryId,
                amount: Money(r.amountMinor, Currency.fromCode(r.currencyCode)),
                startMonth: YearMonth.fromKey(r.startMonth),
                endMonth: r.endMonth == null ? null : YearMonth.fromKey(r.endMonth!),
              ))
          .toList());

  @override
  Future<void> setBudget({
    required String? categoryId,
    required Money amount,
    required YearMonth fromMonth,
  }) {
    if (amount.isNegative || !amount.isWithinLimits) {
      throw ArgumentError('must be >= 0 and <= Money.maxMinor', 'amount');
    }
    return _db.transaction(() async {
      await _endActive(categoryId, fromMonth);
      await _db.into(_b).insert(BudgetsCompanion.insert(
            id: newId(),
            categoryId: Value(categoryId),
            amountMinor: amount.minor,
            currencyCode: amount.currency.code,
            startMonth: fromMonth.key,
          ));
    });
  }

  @override
  Future<void> removeBudget({required String? categoryId, required YearMonth fromMonth}) =>
      _db.transaction(() => _endActive(categoryId, fromMonth));

  /// Clears the budget from [month] onwards: rows starting in or after
  /// [month] are soft-deleted, the earlier active row gets `endMonth = month - 1`.
  /// This guarantees budget periods never overlap.
  Future<void> _endActive(String? categoryId, YearMonth month) async {
    final now = DateTime.now();
    await (_db.update(_b)
          ..where((b) =>
              b.deletedAt.isNull() &
              _forCategory(categoryId) &
              b.startMonth.isBiggerOrEqualValue(month.key)))
        .write(BudgetsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
    await (_db.update(_b)..where((b) => _activeIn(month) & _forCategory(categoryId))).write(
      BudgetsCompanion(endMonth: Value(month.previous.key), updatedAt: Value(now)),
    );
  }
}

class DriftRecurringItemRepository implements RecurringItemRepository {
  DriftRecurringItemRepository(this._db);

  final AppDatabase _db;

  static const _maxInterval = 366;

  @override
  Stream<List<RecurringItem>> watchAll({RecurringKind? kind}) {
    final query = _db.select(_db.recurringItems)
      ..where((r) =>
          r.deletedAt.isNull() & (kind == null ? const Constant(true) : r.kind.equalsValue(kind)))
      ..orderBy([(r) => OrderingTerm.asc(r.name)]);
    return query.watch().map((rows) => rows
        .map((r) => RecurringItem(
              id: r.id,
              kind: r.kind,
              name: r.name,
              amount: Money(r.amountMinor, Currency.fromCode(r.currencyCode)),
              rule: RecurrenceRule(r.frequency, interval: r.interval),
              anchorDate: r.anchorDate,
              endDate: r.endDate,
              postedFrom: r.postedFrom,
              categoryId: r.categoryId,
              paymentMethodId: r.paymentMethodId,
              isActive: r.isActive,
              notes: r.notes,
            ))
        .toList());
  }

  @override
  Future<void> save(RecurringItem item) {
    final name = item.name.trim();
    if (name.isEmpty || name.length > 80) throw ArgumentError('must be 1-80 characters', 'name');
    if (!item.amount.isPositive || !item.amount.isWithinLimits) {
      throw ArgumentError('must be > 0 and <= Money.maxMinor', 'amount');
    }
    if (item.rule.interval > _maxInterval) throw ArgumentError('too large', 'interval');
    if (item.endDate != null && item.endDate!.isBefore(item.anchorDate)) {
      throw ArgumentError('must not be before anchorDate', 'endDate');
    }
    return _db.into(_db.recurringItems).insertOnConflictUpdate(
          RecurringItemsCompanion.insert(
            id: item.id,
            kind: item.kind,
            name: name,
            amountMinor: item.amount.minor,
            currencyCode: item.amount.currency.code,
            frequency: item.rule.frequency,
            interval: Value(item.rule.interval),
            anchorDate: item.anchorDate,
            endDate: Value(item.endDate),
            postedFrom: Value(item.postedFrom),
            categoryId: Value(item.categoryId),
            paymentMethodId: Value(item.paymentMethodId),
            isActive: Value(item.isActive),
            notes: Value(item.notes),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  @override
  Future<void> delete(String id) {
    final now = DateTime.now();
    return (_db.update(_db.recurringItems)..where((r) => r.id.equals(id)))
        .write(RecurringItemsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
  }
}
