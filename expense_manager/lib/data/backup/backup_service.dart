import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../core/time/year_month.dart';
import '../../core/utils/ids.dart';
import '../../domain/backup/backup_policy.dart';
import '../database/app_database.dart';
import 'backup_codec.dart';
import 'backup_crypto.dart';
import 'backup_storage.dart';

/// Manual / automatic backups, validation and restore.
class BackupService {
  BackupService(this._db, this._storage, {Clock clock = systemClock})
      : _codec = BackupCodec(_db),
        _clock = clock;

  final AppDatabase _db;
  final BackupStorage _storage;
  final BackupCodec _codec;
  final Clock _clock;

  /// Newest first.
  Stream<List<BackupRecord>> watchBackups() => (_db.select(_db.backupRecords)
        ..orderBy([(b) => OrderingTerm.desc(b.createdAt)]))
      .watch();

  Future<BackupRecord> create(BackupOrigin origin) async {
    final now = _clock();
    final content = await _codec.encode(now: now);
    final fileName = 'backup_${_stamp(now)}_${origin.name}_${newId().substring(0, 8)}.json';
    final size = await _storage.write(fileName, content);
    final record = BackupRecord(
      id: newId(),
      fileName: fileName,
      location: _storage.location,
      sizeBytes: size,
      sha256: sha256.convert(utf8.encode(content)).toString(),
      schemaVersion: AppDatabase.currentSchemaVersion,
      origin: origin.name,
      createdAt: now,
    );
    await _db.into(_db.backupRecords).insert(record);
    try {
      await _prune(origin);
    } on Object {
      // The backup itself succeeded; old files are pruned next time.
    }
    return record;
  }

  /// Creates an automatic backup when the schedule says so. Returns whether
  /// one was made. Any backup except safety copies (manual too) resets the
  /// schedule.
  Future<bool> runAutomaticIfDue(BackupFrequency frequency) async {
    if (frequency == BackupFrequency.off) return false;
    final last = await (_db.select(_db.backupRecords)
          ..where((b) => b.origin.isNotValue(BackupOrigin.safety.name))
          ..orderBy([(b) => OrderingTerm.desc(b.createdAt)])
          ..limit(1))
        .getSingleOrNull();
    if (!BackupPolicy.isDue(frequency, last?.createdAt, _clock())) return false;
    await create(BackupOrigin.automatic);
    return true;
  }

  Future<void> restore(BackupRecord record) async => restoreFromContent(await read(record));

  /// Plain JSON of a stored backup (e.g. to encrypt it for export).
  Future<String> read(BackupRecord record) => _storage.read(record.fileName);

  /// Restores a backup file chosen by the user (e.g. from another phone).
  /// Encrypted files are decrypted with the passphrase from [askPassphrase].
  /// Returns false when the user cancels the passphrase prompt.
  Future<bool> restoreFromFile(String path, {Future<String?> Function()? askPassphrase}) async {
    final file = File(path);
    // Encrypted files are base64 (~4/3 larger); the plain JSON inside is
    // checked against maxBytes again when parsed.
    if (await file.length() > BackupCodec.maxBytes * 2) {
      throw const BackupException(BackupError.tooLarge);
    }
    String content;
    try {
      content = await file.readAsString();
    } on FileSystemException {
      throw const BackupException(BackupError.notABackup);
    }
    if (isEncryptedBackup(content)) {
      final passphrase = await askPassphrase?.call();
      if (passphrase == null) return false;
      content = await decryptBackup(content, passphrase);
    }
    await restoreFromContent(content);
    return true;
  }

  /// Validates and restores plain backup JSON, keeping a safety copy first.
  Future<void> restoreFromContent(String content) async {
    final backup = await BackupCodec.validate(content); // throws before anything changes
    await create(BackupOrigin.safety); // lets the user undo a bad restore
    await _codec.restore(backup);
  }

  Future<void> delete(BackupRecord record) async {
    await _storage.delete(record.fileName);
    await (_db.delete(_db.backupRecords)..where((b) => b.id.equals(record.id))).go();
  }

  Future<String> pathOf(BackupRecord record) => _storage.pathOf(record.fileName);

  Future<void> _prune(BackupOrigin origin) async {
    final keep = switch (origin) {
      BackupOrigin.manual => null,
      BackupOrigin.automatic => BackupPolicy.keepAutomatic,
      BackupOrigin.safety => BackupPolicy.keepSafety,
    };
    if (keep == null) return;
    final records = await (_db.select(_db.backupRecords)
          ..where((b) => b.origin.equals(origin.name))
          ..orderBy([(b) => OrderingTerm.desc(b.createdAt)]))
        .get();
    final byId = {for (final r in records) r.id: r};
    for (final id in BackupPolicy.toPrune(records.map((r) => r.id).toList(), keep)) {
      await delete(byId[id]!);
    }
  }

  static String _stamp(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}${two(d.month)}${two(d.day)}_${two(d.hour)}${two(d.minute)}${two(d.second)}';
  }
}
