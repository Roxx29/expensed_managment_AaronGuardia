import 'package:drift/drift.dart';

import '../../domain/entities/entities.dart';
import '../../domain/repositories/repositories.dart';
import '../database/app_database.dart';

class DriftWalletRepository implements WalletRepository {
  DriftWalletRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<List<Wallet>> watchAll() {
    final query = _db.select(_db.wallets)
      ..where((w) => w.deletedAt.isNull())
      ..orderBy([(w) => OrderingTerm.asc(w.name)]);
    return query.watch().map((rows) => [for (final r in rows) toEntity(r)]);
  }

  @override
  Future<void> save(Wallet wallet, {bool placeholder = false}) {
    final name = wallet.name.trim();
    // Messages never include user content.
    if (name.isEmpty || name.length > 50) throw ArgumentError('must be 1-50 characters', 'name');
    return _db.into(_db.wallets).insertOnConflictUpdate(WalletsCompanion.insert(
          id: wallet.id,
          name: name,
          kind: wallet.kind,
          secret: wallet.secret,
          ownerUid: Value(wallet.ownerUid),
          updatedAt: Value(placeholder ? DateTime.utc(2000) : DateTime.now()),
          deletedAt: const Value(null),
        ));
  }

  @override
  Future<void> delete(String id) {
    final now = DateTime.now();
    return (_db.update(_db.wallets)..where((w) => w.id.equals(id)))
        .write(WalletsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
  }

  @override
  Future<void> setOwner(String id, String ownerUid) =>
      (_db.update(_db.wallets)..where((w) => w.id.equals(id))).write(WalletsCompanion(ownerUid: Value(ownerUid)));

  static Wallet toEntity(WalletRecord r) =>
      Wallet(id: r.id, name: r.name, kind: r.kind, secret: r.secret, ownerUid: r.ownerUid);
}
