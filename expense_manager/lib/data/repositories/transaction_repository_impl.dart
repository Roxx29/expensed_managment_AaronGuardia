import 'package:drift/drift.dart';

import '../../core/money/currency.dart';
import '../../core/money/money.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/repositories.dart';
import '../database/app_database.dart';

class DriftTransactionRepository implements TransactionRepository {
  DriftTransactionRepository(this._db);

  final AppDatabase _db;

  $TransactionsTable get _t => _db.transactions;

  @override
  Stream<List<FinanceTransaction>> watchBetween(DateTime from, DateTime toExclusive) {
    final query = _db.select(_t)
      ..where((t) =>
          t.deletedAt.isNull() &
          t.walletId.isNull() &
          t.occurredAt.isBiggerOrEqualValue(from) &
          t.occurredAt.isSmallerThanValue(toExclusive))
      ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]);
    return query.watch().map((rows) => rows.map(_toEntity).toList());
  }

  @override
  Stream<List<FinanceTransaction>> watchRecent({int limit = 10}) {
    final query = _db.select(_t)
      ..where((t) => t.deletedAt.isNull() & t.walletId.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)])
      ..limit(limit);
    return query.watch().map((rows) => rows.map(_toEntity).toList());
  }

  // ponytail: loads the full history; add DB-side filtering/paging when a user
  // reaches tens of thousands of transactions.
  @override
  Stream<List<FinanceTransaction>> watchAll() {
    final query = _db.select(_t)
      ..where((t) => t.deletedAt.isNull() & t.walletId.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]);
    return query.watch().map((rows) => rows.map(_toEntity).toList());
  }

  @override
  Stream<List<FinanceTransaction>> watchWallet(String walletId) {
    final query = _db.select(_t)
      ..where((t) => t.deletedAt.isNull() & t.walletId.equals(walletId))
      ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]);
    return query.watch().map((rows) => rows.map(_toEntity).toList());
  }

  @override
  Future<FinanceTransaction?> getById(String id) async {
    final row = await (_db.select(_t)
          ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
        .getSingleOrNull();
    return row == null ? null : _toEntity(row);
  }

  @override
  Stream<Map<TransactionType, Money>> watchTotalsByType(Currency currency) {
    final total = _t.amountMinor.sum();
    final query = _db.selectOnly(_t)
      ..addColumns([_t.type, total])
      ..where(_t.deletedAt.isNull() & _t.walletId.isNull() & _t.currencyCode.equals(currency.code))
      ..groupBy([_t.type]);
    return query.watch().map((rows) => {
          for (final row in rows)
            row.readWithConverter(_t.type)!:
                Money(row.read(total) ?? 0, currency),
        });
  }

  @override
  Future<void> save(FinanceTransaction tx) {
    _validate(tx);
    return _db.into(_t).insertOnConflictUpdate(_toCompanion(tx));
  }

  @override
  Future<void> insertMissing(List<FinanceTransaction> transactions) {
    transactions.forEach(_validate);
    return _db.batch((b) => b.insertAll(
          _t,
          transactions.map(_toCompanion).toList(),
          mode: InsertMode.insertOrIgnore,
        ));
  }

  static TransactionsCompanion _toCompanion(FinanceTransaction tx) => TransactionsCompanion.insert(
            id: tx.id,
            type: tx.type,
            amountMinor: tx.amount.minor,
            currencyCode: tx.amount.currency.code,
            occurredAt: tx.occurredAt,
            description: Value(tx.description.trim()),
            categoryId: Value(tx.categoryId),
            paymentMethodId: Value(tx.paymentMethodId),
            recurringItemId: Value(tx.recurringItemId),
            savingsGoalId: Value(tx.savingsGoalId),
            source: Value(tx.source),
            notes: Value(tx.notes),
            project: Value(tx.project?.trim().isEmpty ?? true ? null : tx.project!.trim()),
            walletId: Value(tx.walletId),
            createdBy: Value(tx.createdBy),
            updatedAt: Value(DateTime.now()),
            deletedAt: const Value(null),
          );

  @override
  Future<void> delete(String id) {
    final now = DateTime.now();
    return (_db.update(_t)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }

  static const _maxDescriptionLength = 200;
  static const _maxNotesLength = 1000;

  /// Also checked in backup_codec.dart and the transaction form.
  static const maxProjectLength = 60;

  void _validate(FinanceTransaction tx) {
    // Messages never include user content (it may reach crash reports later).
    if (tx.id.isEmpty) throw ArgumentError('must not be empty', 'id');
    if (!tx.amount.isPositive || !tx.amount.isWithinLimits) {
      throw ArgumentError('must be > 0 and <= Money.maxMinor', 'amount');
    }
    if (tx.description.length > _maxDescriptionLength) {
      throw ArgumentError('too long', 'description');
    }
    if ((tx.notes?.length ?? 0) > _maxNotesLength) throw ArgumentError('too long', 'notes');
    if ((tx.source?.length ?? 0) > _maxDescriptionLength) throw ArgumentError('too long', 'source');
    if ((tx.project?.length ?? 0) > maxProjectLength) throw ArgumentError('too long', 'project');
    if ((tx.walletId?.length ?? 0) > 64) throw ArgumentError('too long', 'walletId');
    if ((tx.createdBy?.length ?? 0) > 128) throw ArgumentError('too long', 'createdBy');
  }

  static FinanceTransaction _toEntity(TransactionRecord r) => FinanceTransaction(
        id: r.id,
        type: r.type,
        amount: Money(r.amountMinor, Currency.fromCode(r.currencyCode)),
        occurredAt: r.occurredAt,
        description: r.description,
        categoryId: r.categoryId,
        paymentMethodId: r.paymentMethodId,
        recurringItemId: r.recurringItemId,
        savingsGoalId: r.savingsGoalId,
        source: r.source,
        notes: r.notes,
        project: r.project,
        walletId: r.walletId,
        createdBy: r.createdBy,
      );
}
