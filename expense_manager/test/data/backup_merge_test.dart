import 'package:expense_manager/data/backup/backup_codec.dart';
import 'package:expense_manager/data/database/app_database.dart';
import 'package:expense_manager/domain/entities/entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime(2026, 10, 1, 9);
  final t1 = DateTime(2026, 10, 2, 9);

  TransactionRecord tx(String id, int minor, DateTime updatedAt, {DateTime? deletedAt}) => TransactionRecord(
        id: id,
        createdAt: t0,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
        type: TransactionType.expense,
        amountMinor: minor,
        currencyCode: 'USD',
        description: '',
        occurredAt: t0,
      );

  ValidatedBackup backup(List<TransactionRecord> transactions, {List<SettingRecord> settings = const []}) =>
      ValidatedBackup(
        createdAt: t0,
        profiles: const [],
        categories: const [],
        paymentMethods: const [],
        recurringItems: const [],
        savingsGoals: const [],
        transactions: transactions,
        budgets: const [],
        settings: settings,
      );

  Map<String, int> amounts(ValidatedBackup b) => {for (final t in b.transactions) t.id: t.amountMinor};

  test('the newer row wins on each side and rows from both sides are kept', () {
    final result = mergeBackups(
      backup([tx('a', 100, t1), tx('b', 200, t0), tx('local', 1, t0)]),
      backup([tx('a', 999, t0), tx('b', 222, t1), tx('remote', 2, t0)]),
    );
    expect(amounts(result.merged), {'a': 100, 'b': 222, 'local': 1, 'remote': 2});
    expect(result.localChanged, isTrue); // b and remote come from the cloud
    expect(result.remoteChanged, isTrue); // a and local go to the cloud
  });

  test('a deletion travels like an edit', () {
    final result = mergeBackups(
      backup([tx('a', 100, t0)]),
      backup([tx('a', 100, t1, deletedAt: t1)]),
    );
    expect(result.merged.transactions.single.deletedAt, t1);
    expect(result.localChanged, isTrue);
    expect(result.remoteChanged, isFalse);
  });

  test('same data on both sides changes nothing', () {
    final same = mergeBackups(backup([tx('a', 100, t0)]), backup([tx('a', 100, t0)]));
    expect(same.localChanged, isFalse);
    expect(same.remoteChanged, isFalse);
  });

  test('a tie (same second, different data) is decided the same way on every phone', () {
    final onA = mergeBackups(backup([tx('a', 100, t0)]), backup([tx('a', 5, t0)]));
    final onB = mergeBackups(backup([tx('a', 5, t0)]), backup([tx('a', 100, t0)]));
    expect(amounts(onA.merged), amounts(onB.merged));
    // Exactly one phone takes the other's row; the other one has to upload.
    expect(onA.localChanged, isNot(onB.localChanged));
    expect(onA.remoteChanged, isNot(onB.remoteChanged));
  });

  test('the profile stays this phone\'s', () {
    ProfileRecord profile(String name, DateTime at) =>
        ProfileRecord(id: 'local_profile', createdAt: t0, updatedAt: at, name: name, currencyCode: 'USD');
    ValidatedBackup withProfile(ProfileRecord p) => ValidatedBackup(
          createdAt: t0,
          profiles: [p],
          categories: const [],
          paymentMethods: const [],
          recurringItems: const [],
          savingsGoals: const [],
          transactions: const [],
          budgets: const [],
          settings: const [],
        );
    final result = mergeBackups(withProfile(profile('Ana', t0)), withProfile(profile('Luis', t1)));
    expect(result.merged.profiles.single.name, 'Ana');
    expect(result.localChanged, isFalse);
  });

  test('settings stay those of this phone', () {
    const mine = SettingRecord(key: 'theme_mode', value: 'dark');
    final result = mergeBackups(
      backup(const [], settings: const [mine]),
      backup(const [], settings: const [SettingRecord(key: 'theme_mode', value: 'light')]),
    );
    expect(result.merged.settings, [mine]);
    expect(result.localChanged, isFalse);
  });
}
