import 'dart:io';

import 'package:expense_manager/core/l10n/strings_es.dart';
import 'package:expense_manager/core/money/currency.dart';
import 'package:expense_manager/data/database/default_data.dart';
import 'package:expense_manager/features/profile/application/profile_providers.dart';
import 'package:flutter_test/flutter_test.dart';

final _placeholder = RegExp(r'\{\w+\}');

void main() {
  test('every tr(\'...\') key in lib/ has a Spanish translation', () {
    final key = RegExp(r"""\.tr\(\s*'((?:[^'\\]|\\.)*)'""");
    final missing = <String>{};
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      for (final m in key.allMatches(file.readAsStringSync())) {
        final en = m.group(1)!.replaceAll(r"\'", "'");
        if (!esStrings.containsKey(en)) missing.add(en);
      }
    }
    expect(missing, isEmpty);
  });

  test('keys passed to tr() at runtime are translated too', () {
    const dynamicKeys = [
      // Navigation, More menu, coming-soon screen.
      'Home', 'Transactions', 'Budgets', 'Statistics', 'More', 'Subscriptions',
      'Recurring expenses', 'Savings goals', 'Categories & payment methods',
      'Profile', 'Backup & restore', 'Settings', 'Phase 5',
    ];
    for (final en in [...dynamicKeys, ...countries.values, for (final c in Currency.values) c.displayName]) {
      expect(esStrings, contains(en));
    }
    for (final item in [...defaultCategories.map((c) => c.name), ...defaultPaymentMethods.map((m) => m.name)]) {
      expect(esDefaultNames, contains(item));
    }
  });

  test('translations keep the same placeholders', () {
    esStrings.forEach((en, es) {
      expect(_placeholder.allMatches(es).map((m) => m[0]).toSet(),
          _placeholder.allMatches(en).map((m) => m[0]).toSet(),
          reason: en);
    });
  });
}
