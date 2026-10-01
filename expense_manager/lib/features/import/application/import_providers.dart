import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/import/csv_reader.dart';
import '../../../domain/import/statement_import.dart';
import '../../../shared/providers/providers.dart';

/// A picked CSV file, parsed into rows (first row = header).
class PickedStatement {
  const PickedStatement(this.fileName, this.rows);

  final String fileName;
  final List<List<String>> rows;
}

final importActionsProvider = Provider<ImportActions>(ImportActions.new);

class ImportActions {
  ImportActions(this._ref);

  final Ref _ref;

  /// Lets the user pick a CSV file. Null if cancelled.
  /// Throws [FormatException] if it is too large or malformed.
  Future<PickedStatement?> pickStatement() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'txt'],
    );
    final picked = files.firstOrNull;
    final path = picked?.path;
    if (path == null) return null;
    final file = File(path);
    if (await file.length() > maxCsvBytes) throw const FormatException('CSV file too large');
    final bytes = await file.readAsBytes();
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      // Many banks export Windows-1252/Latin-1; decode that instead of
      // turning every accent into "�".
      text = latin1.decode(bytes);
    }
    return PickedStatement(picked!.name, parseCsv(text));
  }

  /// Day-first unless the profile country is the US.
  bool get prefersMonthFirst => _ref.read(profileProvider).value?.countryCode == 'US';

  /// Saves [transactions] (uncategorized). Rows imported before are skipped
  /// because their IDs are deterministic.
  Future<void> importAll(List<ImportedTransaction> transactions) => _ref
      .read(transactionRepositoryProvider)
      .insertMissing([for (final t in transactions) t.toTransaction()]);
}
