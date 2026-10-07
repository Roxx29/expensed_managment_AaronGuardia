import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/strings_es.dart';
import '../../../domain/import/category_memory.dart';
import '../../../domain/import/csv_reader.dart';
import '../../../domain/import/statement_import.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/common_widgets.dart' show categoryColors;
import '../../premium/application/premium_providers.dart';
import '../../premium/application/usage_ping.dart';

/// App setting: '1' once a free user has used the free import.
const _freeImportUsedKey = 'import.free_used';

/// True when the next import needs Premium.
final importNeedsPremiumProvider = StreamProvider<bool>((ref) {
  final premium = ref.watch(premiumProvider);
  return ref.watch(settingsRepositoryProvider).watch(_freeImportUsedKey).map((v) => !premium && v == '1');
});

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

  /// Saves [imported] with a category: the one named in the file (created
  /// when new) or the one used before for the same merchant. Rows imported
  /// before are skipped because their IDs are deterministic. Uses up the
  /// free import of a free user.
  Future<void> importAll(List<ImportedTransaction> imported) async {
    _ref.read(usageTrackerProvider).track('csv_import');
    final categories = await _ref.read(categoryRepositoryProvider).watchAll(includeArchived: true).first;
    final idByName = <String, String>{};
    // Archived first, so an active category with the same name wins.
    for (final c in [...categories.where((c) => c.archived), ...categories.where((c) => !c.archived)]) {
      idByName[foldText(c.name)] = c.id;
      final spanish = c.isDefault ? esDefaultNames[c.name] : null;
      if (spanish != null) idByName[foldText(spanish)] = c.id;
    }
    final transactions = _ref.read(transactionRepositoryProvider);
    final assignment = assignCategories(
      imported,
      idByName: idByName,
      memory: learnCategories(await transactions.watchAll().first),
      newCategoryColor: categoryColors.first,
    );
    // A renamed or archived imported category keeps its id: reuse it as is.
    final existingIds = {for (final c in categories) c.id};
    final premium = _ref.read(premiumProvider);
    // All or nothing, so "Nothing was changed" is true when it fails.
    await _ref.read(appDatabaseProvider).transaction(() async {
      for (final c in assignment.newCategories) {
        if (!existingIds.contains(c.id)) await _ref.read(categoryRepositoryProvider).save(c);
      }
      await transactions.insertMissing(assignment.transactions);
      if (!premium) await _ref.read(settingsRepositoryProvider).write(_freeImportUsedKey, '1');
    });
  }
}
