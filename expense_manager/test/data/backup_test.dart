// Backup/restore against a real in-memory SQLite database.
@Tags(['db'])
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:expense_manager/core/money/currency.dart';
import 'package:expense_manager/core/money/money.dart';
import 'package:expense_manager/data/backup/backup_codec.dart';
import 'package:expense_manager/data/backup/backup_service.dart';
import 'package:expense_manager/data/backup/backup_storage.dart';
import 'package:expense_manager/data/database/app_database.dart';
import 'package:expense_manager/data/repositories/profile_settings_repositories_impl.dart';
import 'package:expense_manager/data/repositories/transaction_repository_impl.dart';
import 'package:expense_manager/data/repositories/wallet_repository_impl.dart';
import 'package:expense_manager/domain/backup/backup_policy.dart';
import 'package:expense_manager/domain/entities/entities.dart';
import 'package:flutter_test/flutter_test.dart';

/// Keeps "files" in memory.
class MemoryStorage implements BackupStorage {
  final files = <String, String>{};

  @override
  String get location => 'memory';

  @override
  Future<int> write(String fileName, String content) async {
    files[fileName] = content;
    return utf8.encode(content).length;
  }

  @override
  Future<String> read(String fileName) async => files[fileName]!;

  @override
  Future<void> delete(String fileName) async => files.remove(fileName);

  @override
  Future<String> pathOf(String fileName) async => '/memory/$fileName';
}

void main() {
  late AppDatabase db;
  late MemoryStorage storage;
  late BackupService service;
  late DriftTransactionRepository transactions;
  var now = DateTime(2026, 9, 30, 10);

  FinanceTransaction expense(String id, int minor) => FinanceTransaction(
        id: id,
        type: TransactionType.expense,
        amount: Money(minor, Currency.usd),
        occurredAt: DateTime(2026, 9, 5),
        categoryId: 'cat_food',
      );

  setUp(() {
    now = DateTime(2026, 9, 30, 10);
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
    storage = MemoryStorage();
    service = BackupService(db, storage, clock: () => now);
    transactions = DriftTransactionRepository(db);
  });
  tearDown(() => db.close());

  test('backup → change data → restore brings the data back and keeps a safety copy', () async {
    await transactions.save(expense('a', 1000));
    await DriftSettingsRepository(db).write('theme_mode', 'dark');
    final backup = await service.create(BackupOrigin.manual);

    await transactions.save(expense('b', 2000));
    await transactions.delete('a');
    await DriftSettingsRepository(db).write('theme_mode', 'light');

    await service.restore(backup);

    final list = await transactions.watchAll().first;
    expect(list.map((t) => t.id), ['a']);
    expect(list.single.amount, const Money(1000, Currency.usd));
    expect(await DriftSettingsRepository(db).read('theme_mode'), 'dark');

    final records = await service.watchBackups().first;
    expect(records.map((r) => r.origin), containsAll(['manual', 'safety']));
  });

  test('the project of a transaction survives backup and restore', () async {
    await transactions.save(FinanceTransaction(
      id: 'p',
      type: TransactionType.expense,
      amount: const Money(500, Currency.usd),
      occurredAt: DateTime(2026, 9, 5),
      project: 'Acme',
    ));
    final backup = await service.create(BackupOrigin.manual);
    await transactions.delete('p');
    await service.restore(backup);
    expect((await transactions.watchAll().first).single.project, 'Acme');
  });

    test('security settings are never exported', () async {
    await DriftSettingsRepository(db).write('security.pin_hash', 'secret');
    final content = await BackupCodec(db).encode();
    expect(content, isNot(contains('secret')));
  });

  group('rejects bad files without touching data', () {
    late String valid;
    setUp(() async {
      await transactions.save(expense('a', 1000));
      valid = await BackupCodec(db).encode();
    });

    Future<BackupError?> restoreError(String content) async {
      storage.files['bad.json'] = content;
      final record = BackupRecord(
        id: 'x',
        fileName: 'bad.json',
        location: 'memory',
        sizeBytes: content.length,
        sha256: '',
        schemaVersion: 1,
        origin: 'manual',
        createdAt: now,
      );
      try {
        await service.restore(record);
        return null;
      } on BackupException catch (e) {
        return e.error;
      }
    }

    Map<String, dynamic> parsed() => jsonDecode(valid) as Map<String, dynamic>;

    test('not JSON / wrong format', () async {
      expect(await restoreError('hello'), BackupError.notABackup);
      expect(await restoreError('{"format":"other"}'), BackupError.notABackup);
    });

    test('newer schema version', () async {
      final json = parsed()..['schemaVersion'] = AppDatabase.currentSchemaVersion + 1;
      expect(await restoreError(jsonEncode(json)), BackupError.newerVersion);
    });

    test('checksum mismatch (edited file)', () async {
      final json = parsed();
      ((json['data'] as Map<String, dynamic>)['transactions'] as List<dynamic>).clear();
      expect(await restoreError(jsonEncode(json)), BackupError.corrupted);
    });

    test('valid checksum but invalid rows (negative amount) → nothing changes', () async {
      final json = parsed();
      final data = json['data'] as Map<String, dynamic>;
      final tx = (data['transactions'] as List<dynamic>).single as Map<String, dynamic>;
      tx['amountMinor'] = -5;
      json['sha256'] = _sha(data);
      expect(await restoreError(jsonEncode(json)), BackupError.invalidData);
      expect((await transactions.watchAll().first).single.amount.minor, 1000);
    });

    test('broken reference (missing category) → rolled back', () async {
      final json = parsed();
      final data = json['data'] as Map<String, dynamic>;
      ((data['transactions'] as List<dynamic>).single as Map<String, dynamic>)['categoryId'] = 'missing';
      json['sha256'] = _sha(data);
      expect(await restoreError(jsonEncode(json)), BackupError.invalidData);
      expect((await transactions.watchAll().first).single.categoryId, 'cat_food');
    });

    test('impossible budget month', () async {
      final json = parsed();
      final data = json['data'] as Map<String, dynamic>;
      (data['budgets'] as List<dynamic>).add({
        'id': 'b1', 'createdAt': 0, 'updatedAt': 0, 'deletedAt': null, 'categoryId': null,
        'amountMinor': 100, 'currencyCode': 'USD', 'startMonth': 202613, 'endMonth': null,
      });
      json['sha256'] = _sha(data);
      expect(await restoreError(jsonEncode(json)), BackupError.invalidData);
    });

    test('unknown enum value', () async {
      final json = parsed();
      final data = json['data'] as Map<String, dynamic>;
      ((data['transactions'] as List<dynamic>).single as Map<String, dynamic>)['type'] = 'hack';
      json['sha256'] = _sha(data);
      expect(await restoreError(jsonEncode(json)), BackupError.invalidData);
    });

    test('a v1 backup (before projects) still restores', () async {
      final json = parsed()..['schemaVersion'] = 1;
      // Changed after the backup, so the restore must replace it.
      await transactions.save(FinanceTransaction(
        id: 'a',
        type: TransactionType.expense,
        amount: const Money(1000, Currency.usd),
        occurredAt: DateTime(2026, 9, 5),
        categoryId: 'cat_food',
        project: 'X',
      ));
      final data = json['data'] as Map<String, dynamic>;
      ((data['transactions'] as List<dynamic>).single as Map<String, dynamic>).remove('project');
      data.remove('wallets'); // also before shared wallets (schema v3)
      json['sha256'] = _sha(data);
      expect(await restoreError(jsonEncode(json)), isNull);
      expect((await transactions.watchAll().first).single.project, isNull);
    });
  });

  test('sync restore aborts when local data changed since the snapshot', () async {
    final codec = BackupCodec(db);
    await transactions.save(expense('a', 1000));
    final before = await codec.fingerprint();
    final snapshot = BackupCodec.parse(await codec.encode());
    await transactions.save(expense('b', 2000));
    await expectLater(
      codec.restore(snapshot, keepSettings: true, expectFingerprint: before),
      throwsA(isA<LocalDataChanged>()),
    );
    expect((await transactions.watchAll().first).map((t) => t.id).toSet(), {'a', 'b'});
  });

  test('sync restore keeps this phone\'s settings', () async {
    final codec = BackupCodec(db);
    await DriftSettingsRepository(db).write('theme_mode', 'dark');
    final snapshot = BackupCodec.parse(await codec.encode());
    await DriftSettingsRepository(db).write('theme_mode', 'light');
    await codec.restore(snapshot, keepSettings: true, expectFingerprint: await codec.fingerprint());
    expect(await DriftSettingsRepository(db).read('theme_mode'), 'light');
  });

  group('shared wallets', () {
    setUp(() async {
      await DriftWalletRepository(db)
          .save(const Wallet(id: 'w1', name: 'Shop', kind: WalletKind.business, secret: 'k'));
      await transactions.save(expense('personal', 100));
      await transactions.save(FinanceTransaction(
        id: 'shared',
        type: TransactionType.expense,
        amount: const Money(200, Currency.usd),
        occurredAt: DateTime(2026, 9, 6),
        categoryId: 'cat_food',
        walletId: 'w1',
        createdBy: 'u1',
      ));
    });

    test('personal views skip wallet entries', () async {
      expect((await transactions.watchAll().first).map((t) => t.id), ['personal']);
      expect((await transactions.watchWallet('w1').first).map((t) => t.id), ['shared']);
      expect((await transactions.watchWallet('w1').first).single.createdBy, 'u1');
    });

    test('a wallet snapshot holds only that wallet', () async {
      final b = BackupCodec.parse(await BackupCodec(db).encode(walletId: 'w1'));
      expect(b.transactions.map((t) => t.id), ['shared']);
      expect(b.categories.map((c) => c.id), ['cat_food']);
      expect(b.wallets.single.id, 'w1');
      expect(b.profiles, isEmpty);
      expect(b.settings, isEmpty);
      expect(b.budgets, isEmpty);
    });

    test('applying a member snapshot writes only that wallet', () async {
      final codec = BackupCodec(db);
      final json = jsonDecode(await codec.encode(walletId: 'w1')) as Map<String, dynamic>;
      final data = json['data'] as Map<String, dynamic>;
      final list = data['transactions'] as List<dynamic>;
      final shared = list.single as Map<String, dynamic>;
      // A hostile or buggy member: a personal row, an unknown category and a
      // renamed default category.
      list
        ..add({...shared, 'id': 'intruder', 'walletId': null})
        ..add({...shared, 'id': 'new', 'categoryId': 'cat_missing'});
      ((data['categories'] as List<dynamic>).single as Map<String, dynamic>)['name'] = 'Hacked';
      json['sha256'] = _sha(data);
      final remote = scopeToWallet(BackupCodec.parse(jsonEncode(json)), 'w1');
      await codec.applyWallet(remote, 'w1', secret: 'k', expectFingerprint: await codec.walletFingerprint('w1'));

      expect(await transactions.getById('intruder'), isNull);
      final added = await transactions.getById('new');
      expect(added?.walletId, 'w1');
      expect(added?.categoryId, isNull);
      final food = await (db.select(db.categories)..where((c) => c.id.equals('cat_food'))).getSingle();
      expect(food.name, 'Food');
    });
  });

  test('restore keeps this device\'s security settings', () async {
    final backup = await service.create(BackupOrigin.manual);
    await DriftSettingsRepository(db).write('security.pin_hash', 'local');
    await service.restore(backup);
    expect(await DriftSettingsRepository(db).read('security.pin_hash'), 'local');
  });

  test('automatic backups: due check and retention', () async {
    expect(await service.runAutomaticIfDue(BackupFrequency.off), isFalse);
    expect(await service.runAutomaticIfDue(BackupFrequency.daily), isTrue);
    expect(await service.runAutomaticIfDue(BackupFrequency.daily), isFalse); // same day

    for (var i = 1; i <= BackupPolicy.keepAutomatic + 2; i++) {
      now = DateTime(2026, 10, i, 10);
      await service.runAutomaticIfDue(BackupFrequency.daily);
    }
    final automatic = (await service.watchBackups().first).where((b) => b.origin == 'automatic');
    expect(automatic, hasLength(BackupPolicy.keepAutomatic));
    expect(storage.files, hasLength(BackupPolicy.keepAutomatic));
  });
}

/// Same checksum the codec writes, so the test can forge a "valid" file.
String _sha(Map<String, dynamic> data) => sha256.convert(utf8.encode(jsonEncode(data))).toString();
