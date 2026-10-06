import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../core/money/currency.dart';
// Enums are referenced by the generated part file.
import '../../domain/entities/enums.dart';
import 'default_data.dart';
import 'tables.dart';

export 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Profiles,
    Categories,
    PaymentMethods,
    RecurringItems,
    SavingsGoals,
    Transactions,
    Budgets,
    AppSettings,
    BackupRecords,
    Wallets,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'expense_manager'));

  /// Bump on every schema change and add a step in [migration].
  static const int currentSchemaVersion = 3;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seedDefaults();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // v2: project / client on transactions.
            await m.addColumn(transactions, transactions.project);
            // Untouched default rows (updated == created at install) get the
            // old seed date, so a new phone's defaults never win a sync merge.
            for (final t in const ['categories', 'payment_methods']) {
              await customStatement(
                'UPDATE $t SET created_at = ?, updated_at = ? WHERE is_default = 1 AND updated_at = created_at',
                [_seedSeconds, _seedSeconds],
              );
            }
          }
          if (from < 3) {
            // v3: shared wallets.
            await m.createTable(wallets);
            await m.addColumn(transactions, transactions.walletId);
            await m.addColumn(transactions, transactions.createdBy);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// 2000-01-01 UTC in Drift's storage (unix seconds): seeded rows are older
  /// than any edit, so sync never prefers an untouched default.
  static const _seedSeconds = 946684800;
  static final _seedDate = DateTime.fromMillisecondsSinceEpoch(_seedSeconds * 1000, isUtc: true);

  Future<void> _seedDefaults() => batch((b) {
        b.insertAll(categories, [
          for (final c in defaultCategories)
            CategoriesCompanion.insert(
              id: c.id,
              name: c.name,
              iconKey: c.iconKey,
              color: c.color,
              kind: c.kind,
              isDefault: const Value(true),
              sortOrder: Value(c.sortOrder),
              createdAt: Value(_seedDate),
              updatedAt: Value(_seedDate),
            ),
        ]);
        b.insertAll(paymentMethods, [
          for (final p in defaultPaymentMethods)
            PaymentMethodsCompanion.insert(
              id: p.id,
              name: p.name,
              type: p.type,
              isDefault: const Value(true),
              createdAt: Value(_seedDate),
              updatedAt: Value(_seedDate),
            ),
        ]);
        b.insert(
          profiles,
          ProfilesCompanion.insert(
            id: localProfileId,
            currencyCode: Currency.fallback.code,
          ),
        );
      });
}

