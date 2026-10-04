import 'dart:convert';
import 'dart:io';

/// Where backup files live. Local now; a cloud implementation (Drive,
/// iCloud, Firebase) can implement the same contract later.
abstract interface class BackupStorage {
  /// Stored in `backup_records.location`.
  String get location;

  /// Writes [content] and returns its size in bytes.
  Future<int> write(String fileName, String content);

  Future<String> read(String fileName);

  Future<void> delete(String fileName);

  /// Local path of the file, used to share/export it.
  Future<String> pathOf(String fileName);
}

/// Files in the app's private support directory (not Documents, so they are
/// not exposed in the iOS Files app).
class LocalBackupStorage implements BackupStorage {
  LocalBackupStorage(this._baseDirectory);

  final Future<Directory> Function() _baseDirectory;

  /// App-generated names only: no separators, no "..".
  static final _safeName = RegExp(r'^[A-Za-z0-9_\-]+\.json$');

  @override
  String get location => 'local';

  Future<File> _file(String fileName) async {
    if (!_safeName.hasMatch(fileName)) throw ArgumentError('invalid backup file name');
    final dir = Directory('${(await _baseDirectory()).path}${Platform.pathSeparator}backups');
    await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}$fileName');
  }

  @override
  Future<int> write(String fileName, String content) async {
    final bytes = utf8.encode(content);
    await (await _file(fileName)).writeAsBytes(bytes, flush: true);
    if (Platform.isAndroid) await _copyToDocuments(fileName, bytes);
    return bytes.length;
  }

  /// A copy the user can see in the phone's file manager. It stays there:
  /// pruning and deleting in the app only touch the private folder.
  // ponytail: primary storage path hard-coded and no permission request, so
  // Android 10 and older (they need WRITE_EXTERNAL_STORAGE) keep only the
  // private copy. Use MediaStore if that matters.
  static Future<void> _copyToDocuments(String fileName, List<int> bytes) async {
    try {
      final dir = Directory(publicBackupFolder);
      await dir.create(recursive: true);
      await File('${dir.path}/$fileName').writeAsBytes(bytes, flush: true);
    } on FileSystemException {
      // Best effort: the private backup above already succeeded.
    }
  }

  @override
  Future<String> read(String fileName) async => (await _file(fileName)).readAsString();

  @override
  Future<void> delete(String fileName) async {
    final file = await _file(fileName);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<String> pathOf(String fileName) async => (await _file(fileName)).path;

  /// Backup files in the folder, newest first. After a reinstall Android can
  /// bring them back from the Google account backup
  /// (android/app/src/main/res/xml/*backup*_rules.xml) without their rows.
  Future<List<String>> list() async {
    final dir = Directory('${(await _baseDirectory()).path}${Platform.pathSeparator}backups');
    if (!await dir.exists()) return const [];
    final names = [
      for (final f in dir.listSync().whereType<File>())
        if (_safeName.hasMatch(f.uri.pathSegments.last)) f.uri.pathSegments.last,
    ];
    return names..sort(compareBackupNames);
  }
}

/// Documents › backupmonchi on the phone (Android).
const publicBackupFolder = '/storage/emulated/0/Documents/backupmonchi';

/// `backup_20261004_153000_manual_ab12cd34.json` → 2026-10-04 15:30:00.
DateTime? backupNameDate(String fileName) {
  final m = RegExp(r'^backup_(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})_').firstMatch(fileName);
  if (m == null) return null;
  final n = [for (var i = 1; i <= 6; i++) int.parse(m.group(i)!)];
  return DateTime(n[0], n[1], n[2], n[3], n[4], n[5]);
}

/// Newest first; names without a date go last.
int compareBackupNames(String a, String b) {
  final da = backupNameDate(a), db = backupNameDate(b);
  if (da == null || db == null) return (da == null ? 1 : 0) - (db == null ? 1 : 0);
  return db.compareTo(da);
}
