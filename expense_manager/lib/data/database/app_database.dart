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
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'expense_manager'));

  /// Bump on every schema change and add a step in [migration].
  static const int currentSchemaVersion = 1;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seedDefaults();
        },
        onUpgrade: (m, from, to) async {
          // Future: `if (from < 2) { await m.addColumn(...); }`
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

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
            ),
        ]);
        b.insertAll(paymentMethods, [
          for (final p in defaultPaymentMethods)
            PaymentMethodsCompanion.insert(
              id: p.id,
              name: p.name,
              type: p.type,
              isDefault: const Value(true),
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

