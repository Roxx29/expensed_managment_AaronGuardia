// More screen layout. Uses an in-memory database, so it carries the `db` tag.
@Tags(['db'])
library;

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:expense_manager/app/app.dart';
import 'package:expense_manager/app/more_screen.dart';
import 'package:expense_manager/data/database/app_database.dart';
import 'package:expense_manager/features/profile/application/profile_providers.dart';
import 'package:expense_manager/shared/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Same setup as test/widget_test.dart.
Future<AppDatabase> _pumpApp(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      // No path_provider plugin in widget tests.
      avatarFileProvider.overrideWith((ref) async => null),
    ],
    child: const ExpenseManagerApp(),
  ));
  await tester.pumpAndSettle();
  return db;
}

Future<void> _dispose(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(const SizedBox());
  await db.close();
}

void main() {
  testWidgets('More lists every section header and each entry once', (tester) async {
    final db = await _pumpApp(tester, const Size(390, 844));

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.byType(MoreScreen), findsOneWidget);

    final list = find.descendant(of: find.byType(MoreScreen), matching: find.byType(Scrollable)).first;
    // The list is lazy and earlier rows may be dropped while scrolling, so
    // check items in on-screen order, scrolling down to each one.
    const ordered = [
      'YOUR MONEY',
      'Wallets',
      'Statistics',
      'PLANNING',
      'TOOLS',
      'DATA & SECURITY',
      'APP',
      'Settings',
    ];
    for (final text in ordered) {
      await tester.scrollUntilVisible(find.text(text), 200, scrollable: list);
      await tester.pumpAndSettle();
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(tester.takeException(), isNull);

    await _dispose(tester, db);
  });
}
