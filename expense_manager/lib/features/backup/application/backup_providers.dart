import 'dart:ui' show Rect;

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/backup/backup_service.dart';
import '../../../data/backup/backup_storage.dart';
import '../../../data/database/app_database.dart';
import '../../../domain/backup/backup_policy.dart';
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
  /// (Drive, email, Files…).
  /// [origin] anchors the share popover on iPad.
  Future<void> export(BackupRecord record, {Rect? origin}) async {
    final path = await _service.pathOf(record);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(path, mimeType: 'application/json')],
      subject: 'Expense Manager backup',
      sharePositionOrigin: origin,
    ));
  }

  /// Lets the user pick a backup file. Returns false if cancelled.
  /// Throws BackupException when the file is invalid.
  Future<bool> restoreFromFile() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    final path = files.firstOrNull?.path;
    if (path == null) return false;
    await _service.restoreFromFile(path);
    return true;
  }
}
