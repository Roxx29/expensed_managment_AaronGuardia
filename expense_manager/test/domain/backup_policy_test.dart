import 'package:expense_manager/domain/backup/backup_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final last = DateTime(2026, 9, 1, 22, 0);

  test('off is never due; no previous backup is always due', () {
    expect(BackupPolicy.isDue(BackupFrequency.off, null, DateTime(2030)), isFalse);
    expect(BackupPolicy.isDue(BackupFrequency.weekly, null, DateTime(2026, 9, 1)), isTrue);
  });

  test('daily is due from the next calendar day', () {
    expect(BackupPolicy.isDue(BackupFrequency.daily, last, DateTime(2026, 9, 1, 23, 59)), isFalse);
    expect(BackupPolicy.isDue(BackupFrequency.daily, last, DateTime(2026, 9, 2, 0, 1)), isTrue);
  });

  test('weekly and monthly', () {
    expect(BackupPolicy.isDue(BackupFrequency.weekly, last, DateTime(2026, 9, 7)), isFalse);
    expect(BackupPolicy.isDue(BackupFrequency.weekly, last, DateTime(2026, 9, 8)), isTrue);
    expect(BackupPolicy.isDue(BackupFrequency.monthly, last, DateTime(2026, 9, 30)), isFalse);
    expect(BackupPolicy.isDue(BackupFrequency.monthly, last, DateTime(2026, 10, 1)), isTrue);
  });

  test('toPrune keeps the newest N', () {
    expect(BackupPolicy.toPrune(['a', 'b', 'c'], 5), isEmpty);
    expect(BackupPolicy.toPrune(['a', 'b', 'c', 'd'], 2), ['c', 'd']);
  });

  test('monthly from Jan 31 is due on Feb 28, not in March', () {
    final jan31 = DateTime(2026, 1, 31);
    expect(BackupPolicy.isDue(BackupFrequency.monthly, jan31, DateTime(2026, 2, 27)), isFalse);
    expect(BackupPolicy.isDue(BackupFrequency.monthly, jan31, DateTime(2026, 2, 28)), isTrue);
  });

  group('shouldRemindCloudBackup', () {
    final now = DateTime(2026, 10, 6, 12);
    bool remind({DateTime? lastUpload, DateTime? snoozedUntil, int transactions = 20}) =>
        BackupPolicy.shouldRemindCloudBackup(
          lastUpload: lastUpload,
          snoozedUntil: snoozedUntil,
          transactionCount: transactions,
          now: now,
        );

    test('never uploaded with enough data reminds', () {
      expect(remind(), isTrue);
    });

    test('too little data to lose does not remind', () {
      expect(remind(transactions: BackupPolicy.remindMinTransactions - 1), isFalse);
      expect(remind(transactions: BackupPolicy.remindMinTransactions), isTrue);
    });

    test('a recent upload does not remind; an old one does', () {
      expect(remind(lastUpload: now.subtract(const Duration(days: 29))), isFalse);
      expect(remind(lastUpload: now.subtract(BackupPolicy.remindAfter)), isTrue);
    });

    test('snoozed until a later date does not remind', () {
      expect(remind(snoozedUntil: now.add(const Duration(minutes: 1))), isFalse);
      expect(remind(snoozedUntil: now), isTrue);
    });
  });
}
