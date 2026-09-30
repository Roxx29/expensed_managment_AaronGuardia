import 'package:drift/drift.dart';

import '../../domain/entities/entities.dart';
import '../../domain/repositories/repositories.dart';
import '../database/app_database.dart';

class DriftCategoryRepository implements CategoryRepository {
  DriftCategoryRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<List<FinanceCategory>> watchAll({bool includeArchived = false}) {
    final query = _db.select(_db.categories)
      ..where((c) =>
          c.deletedAt.isNull() &
          (includeArchived ? const Constant(true) : c.archived.equals(false)))
      ..orderBy([(c) => OrderingTerm.asc(c.sortOrder), (c) => OrderingTerm.asc(c.name)]);
    return query.watch().map((rows) => rows
        .map((r) => FinanceCategory(
              id: r.id,
              name: r.name,
              iconKey: r.iconKey,
              color: r.color,
              kind: r.kind,
              isDefault: r.isDefault,
              sortOrder: r.sortOrder,
              archived: r.archived,
            ))
        .toList());
  }

  @override
  Future<void> save(FinanceCategory c) {
    final name = c.name.trim();
    if (name.isEmpty || name.length > 50) throw ArgumentError('must be 1-50 characters', 'name');
    return _db.into(_db.categories).insertOnConflictUpdate(
          CategoriesCompanion.insert(
            id: c.id,
            name: name,
            iconKey: c.iconKey,
            color: c.color,
            kind: c.kind,
            isDefault: Value(c.isDefault),
            sortOrder: Value(c.sortOrder),
            archived: Value(c.archived),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  /// Categories are archived, never deleted, so history keeps its labels.
  @override
  Future<void> archive(String id) =>
      (_db.update(_db.categories)..where((c) => c.id.equals(id))).write(
        CategoriesCompanion(archived: const Value(true), updatedAt: Value(DateTime.now())),
      );
}

class DriftPaymentMethodRepository implements PaymentMethodRepository {
  DriftPaymentMethodRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<List<PaymentMethod>> watchAll({bool includeArchived = false}) {
    final query = _db.select(_db.paymentMethods)
      ..where((p) =>
          p.deletedAt.isNull() &
          (includeArchived ? const Constant(true) : p.archived.equals(false)))
      ..orderBy([(p) => OrderingTerm.asc(p.name)]);
    return query.watch().map((rows) => rows
        .map((r) => PaymentMethod(
              id: r.id,
              name: r.name,
              type: r.type,
              isDefault: r.isDefault,
              archived: r.archived,
            ))
        .toList());
  }

  @override
  Future<void> save(PaymentMethod p) {
    final name = p.name.trim();
    if (name.isEmpty || name.length > 50) throw ArgumentError('must be 1-50 characters', 'name');
    return _db.into(_db.paymentMethods).insertOnConflictUpdate(
          PaymentMethodsCompanion.insert(
            id: p.id,
            name: name,
            type: p.type,
            isDefault: Value(p.isDefault),
            archived: Value(p.archived),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  @override
  Future<void> archive(String id) =>
      (_db.update(_db.paymentMethods)..where((p) => p.id.equals(id))).write(
        PaymentMethodsCompanion(archived: const Value(true), updatedAt: Value(DateTime.now())),
      );
}
