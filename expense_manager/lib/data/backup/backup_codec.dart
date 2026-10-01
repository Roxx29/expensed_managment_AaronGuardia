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
  const ValidatedBackup._({
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
    // ponytail: older schema versions are accepted as-is while only v1 exists;
    // add JSON migrations here when the schema changes.
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
      backup = ValidatedBackup._(
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
          t.description.length <= 200 && (t.notes?.length ?? 0) <= 1000 && (t.source?.length ?? 0) <= 200) &&
      b.recurringItems.every((r) => r.interval <= 366 && (r.notes?.length ?? 0) <= 1000) &&
      b.settings.every((s) => s.key.length <= 100 && s.value.length <= 10000);

  /// Replaces all user data with [backup] — all or nothing.
  Future<void> restore(ValidatedBackup backup) async {
    try {
      await _db.transaction(() async {
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
        await (_db.delete(_db.appSettings)..where((s) => s.key.like('$securityKeyPrefix%').not())).go();
        await _db.batch((b) {
          b.insertAll(_db.profiles, backup.profiles);
          b.insertAll(_db.categories, backup.categories);
          b.insertAll(_db.paymentMethods, backup.paymentMethods);
          b.insertAll(_db.recurringItems, backup.recurringItems);
          b.insertAll(_db.savingsGoals, backup.savingsGoals);
          b.insertAll(_db.transactions, backup.transactions);
          b.insertAll(_db.budgets, backup.budgets);
          b.insertAll(_db.appSettings, backup.settings);
        });
        // Checked here (not at COMMIT) so a broken reference rolls back reliably.
        if ((await _db.customSelect('PRAGMA foreign_key_check').get()).isNotEmpty) {
          throw const BackupException(BackupError.invalidData);
        }
      });
    } on BackupException {
      rethrow;
    } on Object {
      // Constraint violations (e.g. negative amounts, broken references).
      throw const BackupException(BackupError.invalidData);
    }
  }
}

