import 'dart:io';
import 'dart:ui' show Rect;

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/backup/backup_crypto.dart';
import '../../../data/backup/backup_service.dart';
import '../../../data/backup/backup_storage.dart';
import '../../../data/database/app_database.dart';
import '../../../domain/backup/backup_policy.dart';
import '../../../domain/export/csv_export.dart';
import '../../../shared/providers/providers.dart';

const _frequencyKey = 'backup.frequency';

/// Override with a cloud implementation later.
final backupStorageProvider = Provider<BackupStorage>(
  (ref) => LocalBackupStorage(getApplicationSupportDirectory),
);

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(
    ref.watch(appDatabaseProvider),
    ref.watch(backupStorageProvider),
    clock: ref.watch(clockProvider),
  ),
);

final backupsProvider = StreamProvider<List<BackupRecord>>(
  (ref) => ref.watch(backupServiceProvider).watchBackups(),
);

final backupFrequencyProvider = StreamProvider<BackupFrequency>(
  (ref) => ref
      .watch(settingsRepositoryProvider)
      .watch(_frequencyKey)
      .map((v) => BackupFrequency.values.asNameMap()[v] ?? BackupFrequency.off),
);

/// Runs an automatic backup on launch (and when the schedule changes) if due.
// ponytail: checked on launch only; a background job (WorkManager/BGTask) is
// needed only if users keep the app open for days.
final autoBackupProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(backupServiceProvider);
  final frequency = await ref.watch(backupFrequencyProvider.future);
  try {
    return await service.runAutomaticIfDue(frequency);
  } on Object {
    // Best effort (e.g. disk full): retried on next launch, never blocks the app.
    return false;
  }
});

final backupActionsProvider = Provider<BackupActions>(BackupActions.new);

class BackupActions {
  BackupActions(this._ref);

  final Ref _ref;

  BackupService get _service => _ref.read(backupServiceProvider);

  Future<void> setFrequency(BackupFrequency f) =>
      _ref.read(settingsRepositoryProvider).write(_frequencyKey, f.name);

  Future<BackupRecord> backupNow() => _service.create(BackupOrigin.manual);

  Future<void> restore(BackupRecord record) => _service.restore(record);

  Future<void> delete(BackupRecord record) => _service.delete(record);

  /// Opens the share sheet so the user can save the file elsewhere
  /// (Drive, email, Files…). The file is NOT encrypted.
  /// [origin] anchors the share popover on iPad.
  Future<void> export(BackupRecord record, {Rect? origin}) async =>
      _share(await _service.pathOf(record), 'application/json', origin);

  /// Shares [record] encrypted with [passphrase] (see backup_crypto.dart).
  Future<void> exportEncrypted(BackupRecord record, String passphrase, {Rect? origin}) async {
    final encrypted = await encryptBackup(await _service.read(record), passphrase);
    final file = await _exportFile(record.fileName.replaceFirst(RegExp(r'\.json$'), '.enc.json'));
    await file.writeAsString(encrypted, flush: true);
    await _share(file.path, 'application/json', origin);
  }

  /// Shares all transactions as a CSV spreadsheet (UTF-8 with BOM so Excel
  /// detects the encoding). Names are resolved by the caller in the UI language.
  Future<void> exportTransactionsCsv({
    required String Function(String? categoryId) categoryName,
    String Function(String? id)? paymentMethodName,
    Rect? origin,
  }) async {
    final transactions = await _ref.read(transactionRepositoryProvider).watchAll().first;
    final csv = transactionsToCsv(transactions, categoryName: categoryName, paymentMethodName: paymentMethodName);
    final stamp = DateFormat('yyyyMMdd', 'en_US').format(_ref.read(clockProvider)());
    final file = await _exportFile('transactions_$stamp.csv');
    await file.writeAsString('\uFEFF$csv', flush: true);
    await _share(file.path, 'text/csv', origin);
  }

  /// A file in a temp folder emptied on every export.
  // ponytail: the previous export is deleted at the next export, not right
  // after sharing: on Android the receiving app may still be reading it when
  // share() returns. The OS also clears the cache directory.
  Future<File> _exportFile(String name) async {
    final dir = Directory(p.join((await getTemporaryDirectory()).path, 'exports'));
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } on FileSystemException {
      // Best effort: a leftover export is in the app's private cache.
    }
    await dir.create(recursive: true);
    return File(p.join(dir.path, name));
  }

  Future<void> _share(String path, String mimeType, Rect? origin) => SharePlus.instance.share(ShareParams(
        files: [XFile(path, mimeType: mimeType)],
        subject: 'Expense Manager',
        sharePositionOrigin: origin,
      ));

  /// Lets the user pick a backup file (plain or encrypted). Returns false if
  /// cancelled. Throws BackupException when the file is invalid or the
  /// passphrase is wrong.
  Future<bool> restoreFromFile({required Future<String?> Function() askPassphrase}) async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    final path = files.firstOrNull?.path;
    if (path == null) return false;
    return _service.restoreFromFile(path, askPassphrase: askPassphrase);
  }
}
