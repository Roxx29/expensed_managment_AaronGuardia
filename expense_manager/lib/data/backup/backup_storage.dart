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
    return bytes.length;
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
}
