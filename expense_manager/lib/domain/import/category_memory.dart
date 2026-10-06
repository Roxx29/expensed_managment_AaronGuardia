/// Picks categories for imported rows (pure Dart): the category name in the
/// file, else what the user chose before for the same merchant.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../entities/entities.dart';
import 'statement_import.dart';

final _noise = RegExp(r'[^a-z ]+');
final _spaces = RegExp(r'\s+');

/// "UBER *TRIP 4421 Panamá" → "uber trip panama": bank descriptions differ
/// only in reference numbers and symbols.
String merchantKey(String description) =>
    foldText(description).replaceAll(_noise, ' ').replaceAll(_spaces, ' ').trim();

/// merchant key → category of the newest categorised transaction with it.
/// Learns from the user's own corrections; no extra storage.
Map<String, String> learnCategories(Iterable<FinanceTransaction> history) {
  final newestFirst = history.where((t) => t.categoryId != null).toList()
    ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
  final memory = <String, String>{};
  for (final t in newestFirst) {
    final key = merchantKey(t.description);
    if (key.isNotEmpty) memory.putIfAbsent(key, () => t.categoryId!);
  }
  return memory;
}

class CategoryAssignment {
  const CategoryAssignment(this.transactions, this.newCategories);

  final List<FinanceTransaction> transactions;

  /// Category names from the file that don't exist yet; save them first.
  final List<FinanceCategory> newCategories;
}

/// At most this many categories are created per import (a hostile or messy
/// file could otherwise flood the category picker); later names fall back
/// to the merchant memory.
const maxNewCategories = 50;

/// [idByName]: existing categories by [foldText] of every name they show
/// (stored name and translated default name). New categories get ids derived
/// from the name, so importing the same file again never duplicates them.
CategoryAssignment assignCategories(
  List<ImportedTransaction> imported, {
  required Map<String, String> idByName,
  required Map<String, String> memory,
  required int newCategoryColor,
}) {
  final known = Map.of(idByName);
  final created = <FinanceCategory>[];
  String? categoryFor(ImportedTransaction t) {
    final name = t.categoryName.trim();
    final remembered = memory[merchantKey(t.description)];
    if (name.isEmpty) return remembered;
    final folded = foldText(name);
    if (!known.containsKey(folded) && created.length >= maxNewCategories) return remembered;
    return known.putIfAbsent(folded, () {
      final category = FinanceCategory(
        id: 'cat_imp_${sha256.convert(utf8.encode(folded)).toString().substring(0, 16)}',
        name: name,
        iconKey: 'other',
        color: newCategoryColor,
        kind: CategoryKind.both,
        sortOrder: 1000,
      );
      created.add(category);
      return category.id;
    });
  }

  return CategoryAssignment(
    [for (final t in imported) t.toTransaction(categoryId: categoryFor(t))],
    created,
  );
}
