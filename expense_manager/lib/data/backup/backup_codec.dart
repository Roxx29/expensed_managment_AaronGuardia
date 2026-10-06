import 'dart:convert';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// Why a backup file was rejected. The UI turns these into messages.
enum BackupError { tooLarge, notABackup, newerVersion, corrupted, invalidData, wrongPassphrase }

class BackupException implements Exception {
  const BackupException(this.error);

  final BackupError error;

  @override
  String toString() => 'BackupException(${error.name})';
}

/// A backup that passed validation, parsed into typed rows ready to insert.
class ValidatedBackup {
  const ValidatedBackup({
    required this.createdAt,
    required this.profiles,
    required this.categories,
    required this.paymentMethods,
    required this.recurringItems,
    required this.savingsGoals,
    required this.transactions,
    required this.budgets,
    required this.settings,
  });

  final DateTime createdAt;
  final List<ProfileRecord> profiles;
  final List<CategoryRecord> categories;
  final List<PaymentMethodRecord> paymentMethods;
  final List<RecurringItemRecord> recurringItems;
  final List<SavingsGoalRecord> savingsGoals;
  final List<TransactionRecord> transactions;
  final List<BudgetRecord> budgets;
  final List<SettingRecord> settings;
}

/// Converts the whole database to/from a single JSON document.
///
/// Security: restore treats the file as untrusted input. Only a fixed list of
/// tables is read (names from the file never reach SQL), every row is parsed
/// into a typed record (bad types are rejected), and the insert runs in one
/// transaction where CHECK and foreign-key constraints still apply.
class BackupCodec {
  BackupCodec(this._db);

  final AppDatabase _db;

  static const format = 'expense-manager-backup';
  static const maxBytes = 50 * 1024 * 1024;

  /// Settings under this prefix (PIN/lock state) are never exported or restored.
  static const securityKeyPrefix = 'security.';

  static const _tables = [
    'profiles',
    'categories',
    'paymentMethods',
    'recurringItems',
    'savingsGoals',
    'transactions',
    'budgets',
    'appSettings',
  ];

  Future<String> encode({DateTime? now}) async {
    final data = <String, Object?>{
      'profiles': [for (final r in await _db.select(_db.profiles).get()) r.toJson()],
      'categories': [for (final r in await _db.select(_db.categories).get()) r.toJson()],
      'paymentMethods': [for (final r in await _db.select(_db.paymentMethods).get()) r.toJson()],
      'recurringItems': [for (final r in await _db.select(_db.recurringItems).get()) r.toJson()],
      'savingsGoals': [for (final r in await _db.select(_db.savingsGoals).get()) r.toJson()],
      'transactions': [for (final r in await _db.select(_db.transactions).get()) r.toJson()],
      'budgets': [for (final r in await _db.select(_db.budgets).get()) r.toJson()],
      'appSettings': [
        for (final r in await _db.select(_db.appSettings).get())
          if (!r.key.startsWith(securityKeyPrefix)) r.toJson(),
      ],
    };
    final dataJson = jsonEncode(data);
    return jsonEncode({
      'format': format,
      'schemaVersion': AppDatabase.currentSchemaVersion,
      'createdAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
      // Integrity only (detects corruption), not authenticity.
      'sha256': sha256.convert(utf8.encode(dataJson)).toString(),
      'data': data,
    });
  }

  /// Parses and validates [content] on a background isolate (large files
  /// must not freeze the UI). Throws [BackupException].
  // Static so the isolate closure cannot capture the database connection.
  static Future<ValidatedBackup> validate(String content) => Isolate.run(() => parse(content));

  /// Synchronous parse + validation. Pure: does not touch the database.
  static ValidatedBackup parse(String content) {
    if (content.length > maxBytes) throw const BackupException(BackupError.tooLarge);
    final Object? root;
    try {
      root = jsonDecode(content);
    } on FormatException {
      throw const BackupException(BackupError.notABackup);
    }
    if (root is! Map<String, Object?> || root['format'] != format) {
      throw const BackupException(BackupError.notABackup);
    }
    final version = root['schemaVersion'];
    if (version is! int) throw const BackupException(BackupError.notABackup);
    // v1 backups have no `project`; the nullable column reads as null, so they
    // restore as-is. ponytail: add JSON migrations here when a change is not
    // just a new nullable column.
    if (version > AppDatabase.currentSchemaVersion) {
      throw const BackupException(BackupError.newerVersion);
    }
    final data = root['data'];
    if (data is! Map<String, Object?> || !_tables.every(data.containsKey)) {
      throw const BackupException(BackupError.corrupted);
    }
    if (sha256.convert(utf8.encode(jsonEncode(data))).toString() != root['sha256']) {
      throw const BackupException(BackupError.corrupted);
    }

    final ValidatedBackup backup;
    try {
      List<T> rows<T>(String table, T Function(Map<String, dynamic>) fromJson) =>
          [for (final row in data[table]! as List<Object?>) fromJson(row! as Map<String, dynamic>)];
      backup = ValidatedBackup(
        createdAt: DateTime.parse(root['createdAt']! as String).toLocal(),
        profiles: rows('profiles', ProfileRecord.fromJson),
        categories: rows('categories', CategoryRecord.fromJson),
        paymentMethods: rows('paymentMethods', PaymentMethodRecord.fromJson),
        recurringItems: rows('recurringItems', RecurringItemRecord.fromJson),
        savingsGoals: rows('savingsGoals', SavingsGoalRecord.fromJson),
        transactions: rows('transactions', TransactionRecord.fromJson),
        budgets: rows('budgets', BudgetRecord.fromJson),
        settings: rows('appSettings', SettingRecord.fromJson)
            .where((s) => !s.key.startsWith(securityKeyPrefix))
            .toList(),
      );
    } on Object {
      // Wrong types, unknown enum names, missing fields…
      throw const BackupException(BackupError.invalidData);
    }
    if (!_passesAppRules(backup)) throw const BackupException(BackupError.invalidData);
    return backup;
  }

  static bool _validMonth(int key) => key % 100 >= 1 && key % 100 <= 12;

  /// Rules the database schema cannot express (the repositories enforce them
  /// on normal writes).
  static bool _passesAppRules(ValidatedBackup b) =>
      b.budgets.every((x) =>
          _validMonth(x.startMonth) &&
          (x.endMonth == null || (_validMonth(x.endMonth!) && x.endMonth! >= x.startMonth))) &&
      b.transactions.every((t) =>
          t.description.length <= 200 &&
          (t.notes?.length ?? 0) <= 1000 &&
          (t.source?.length ?? 0) <= 200 &&
          (t.project == null || (t.project!.isNotEmpty && t.project!.trim() == t.project && t.project!.length <= 60))) &&
      b.recurringItems.every((r) => r.interval <= 366 && (r.notes?.length ?? 0) <= 1000) &&
      b.settings.every((s) => s.key.length <= 100 && s.value.length <= 10000);

  /// Tables merged by sync (all have id/updatedAt/deletedAt).
  static const _syncedTables = [
    'profiles',
    'categories',
    'payment_methods',
    'recurring_items',
    'savings_goals',
    'transactions',
    'budgets',
  ];

  /// Changes whenever a synced row is added or edited: row count, newest and
  /// sum of `updated_at` per table (whole seconds: two edits of one row in
  /// the same second look alike, harmless for sync).
  Future<String> fingerprint() async {
    final rows = await _db
        .customSelect(_syncedTables
            .map((t) => "SELECT '$t' AS t, COUNT(*) AS c, MAX(updated_at) AS m, SUM(updated_at) AS s FROM $t")
            .join(' UNION ALL '))
        .get();
    return rows.map((r) => '${r.data['t']}:${r.data['c']}:${r.data['m']}:${r.data['s']}').join('|');
  }

  /// Replaces all user data with [backup] — all or nothing.
  /// A user restore ([keepSettings] false) also marks every row as changed
  /// now, so the restored data wins the next sync on every phone.
  /// [keepSettings]: leave this phone's app settings untouched (sync).
  /// [expectFingerprint]: abort with [LocalDataChanged] when the data changed
  /// since that [fingerprint] (an edit made while a sync was downloading).
  Future<void> restore(ValidatedBackup backup, {bool keepSettings = false, String? expectFingerprint}) async {
    try {
      await _db.transaction(() async {
        if (expectFingerprint != null && await fingerprint() != expectFingerprint) {
          throw const LocalDataChanged();
        }
        await _db.customStatement('PRAGMA defer_foreign_keys = ON');
        // Children before parents.
        await _db.delete(_db.transactions).go();
        await _db.delete(_db.budgets).go();
        await _db.delete(_db.recurringItems).go();
        await _db.delete(_db.savingsGoals).go();
        await _db.delete(_db.categories).go();
        await _db.delete(_db.paymentMethods).go();
        await _db.delete(_db.profiles).go();
        // Security settings (PIN/lock) are device-local: never replaced.
        if (!keepSettings) {
          await (_db.delete(_db.appSettings)..where((s) => s.key.like('$securityKeyPrefix%').not())).go();
        }
        await _db.batch((b) {
          b.insertAll(_db.profiles, backup.profiles);
          b.insertAll(_db.categories, backup.categories);
          b.insertAll(_db.paymentMethods, backup.paymentMethods);
          b.insertAll(_db.recurringItems, backup.recurringItems);
          b.insertAll(_db.savingsGoals, backup.savingsGoals);
          b.insertAll(_db.transactions, backup.transactions);
          b.insertAll(_db.budgets, backup.budgets);
          if (!keepSettings) b.insertAll(_db.appSettings, backup.settings);
        });
        if (!keepSettings) {
          for (final t in _syncedTables) {
            await _db.customStatement("UPDATE $t SET updated_at = CAST(strftime('%s', 'now') AS INTEGER)");
          }
        }
        // Checked here (not at COMMIT) so a broken reference rolls back reliably.
        if ((await _db.customSelect('PRAGMA foreign_key_check').get()).isNotEmpty) {
          throw const BackupException(BackupError.invalidData);
        }
      });
    } on BackupException {
      rethrow;
    } on LocalDataChanged {
      rethrow;
    } on Object {
      // Constraint violations (e.g. negative amounts, broken references).
      throw const BackupException(BackupError.invalidData);
    }
  }
}


/// The local data changed while a sync was running; nothing was replaced.
class LocalDataChanged implements Exception {
  const LocalDataChanged();
}

class MergeResult {
  const MergeResult(this.merged, {required this.localChanged, required this.remoteChanged});

  final ValidatedBackup merged;

  /// Some row came from [remote]: this phone must apply [merged].
  final bool localChanged;

  /// Some row came from [local]: the cloud copy must be replaced by [merged].
  final bool remoteChanged;
}

/// Sync merge: per table and row id, the row with the newer `updatedAt`
/// wins (soft deletions included); a tie is broken by the row's JSON, so
/// every phone picks the same row. App settings and the profile (name,
/// currency, photo path) stay [local]'s: they belong to the phone/person.
MergeResult mergeBackups(ValidatedBackup local, ValidatedBackup remote) {
  var localChanged = false;
  var remoteChanged = false;
  List<T> merge<T extends DataClass>(
    List<T> mine,
    List<T> theirs,
    String Function(T) id,
    DateTime Function(T) updatedAt,
  ) {
    final byId = {for (final r in mine) id(r): r};
    final seen = <String>{};
    for (final r in theirs) {
      final key = id(r);
      seen.add(key);
      final current = byId[key];
      if (current == null) {
        byId[key] = r;
        localChanged = true;
        continue;
      }
      var order = updatedAt(r).compareTo(updatedAt(current));
      if (order == 0 && current != r) order = jsonEncode(r.toJson()).compareTo(jsonEncode(current.toJson()));
      if (order > 0) {
        byId[key] = r;
        localChanged = true;
      } else if (order < 0) {
        remoteChanged = true;
      }
    }
    if (byId.length > seen.length) remoteChanged = true; // rows only on this phone
    return byId.values.toList();
  }

  final merged = ValidatedBackup(
    createdAt: local.createdAt,
    profiles: local.profiles,
    categories: merge(local.categories, remote.categories, (r) => r.id, (r) => r.updatedAt),
    paymentMethods: merge(local.paymentMethods, remote.paymentMethods, (r) => r.id, (r) => r.updatedAt),
    recurringItems: merge(local.recurringItems, remote.recurringItems, (r) => r.id, (r) => r.updatedAt),
    savingsGoals: merge(local.savingsGoals, remote.savingsGoals, (r) => r.id, (r) => r.updatedAt),
    transactions: merge(local.transactions, remote.transactions, (r) => r.id, (r) => r.updatedAt),
    budgets: merge(local.budgets, remote.budgets, (r) => r.id, (r) => r.updatedAt),
    settings: local.settings,
  );
  return MergeResult(merged, localChanged: localChanged, remoteChanged: remoteChanged);
}
