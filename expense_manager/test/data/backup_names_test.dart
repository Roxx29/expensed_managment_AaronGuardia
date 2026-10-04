import 'package:expense_manager/data/backup/backup_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('backup file names carry their date', () {
    expect(backupNameDate('backup_20261004_153000_manual_ab12cd34.json'), DateTime(2026, 10, 4, 15, 30));
    expect(backupNameDate('notes.json'), isNull);
  });

  test('newest backup first, undated names last', () {
    final names = [
      'backup_20260101_000000_automatic_a.json',
      'other.json',
      'backup_20261004_153000_manual_b.json',
    ]..sort(compareBackupNames);
    expect(names, ['backup_20261004_153000_manual_b.json', 'backup_20260101_000000_automatic_a.json', 'other.json']);
  });
}
