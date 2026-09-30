// Widget smoke tests. Uses an in-memory database, so it carries the `db` tag.
@Tags(['db'])
library;

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:expense_manager/app/app.dart';
import 'package:expense_manager/data/database/app_database.dart';
import 'package:expense_manager/shared/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<AppDatabase> _pumpApp(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
  await tester.pumpWidget(ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
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
  testWidgets('phone: dashboard shows empty states and bottom navigation', (tester) async {
    final db = await _pumpApp(tester, const Size(390, 844));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Available money'), findsOneWidget);
    expect(find.text('Your transactions will appear here.'), findsOneWidget);
    expect(tester.takeException(), isNull); // no overflow

    await _dispose(tester, db);
  });

  testWidgets('tablet: uses navigation rail', (tester) async {
    final db = await _pumpApp(tester, const Size(1280, 800));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await _dispose(tester, db);
  });

  testWidgets('settings: switching to dark theme persists', (tester) async {
    final db = await _pumpApp(tester, const Size(390, 844));

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);

    await _dispose(tester, db);
  });

  testWidgets('adding an expense shows it on the dashboard and in history', (tester) async {
    final db = await _pumpApp(tester, const Size(390, 844));

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '12.50');
    await tester.enterText(find.widgetWithText(TextFormField, 'Description'), 'Lunch');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Lunch'), findsOneWidget);
    expect(find.text('−\$12.50'), findsOneWidget);

    await tester.tap(find.text('Transactions'));
    await tester.pumpAndSettle();
    expect(find.text('Lunch'), findsOneWidget);

    await _dispose(tester, db);
  });

  testWidgets('invalid amount shows a validation error', (tester) async {
    final db = await _pumpApp(tester, const Size(390, 844));

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '0');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Amount must be greater than zero'), findsOneWidget);

    await _dispose(tester, db);
  });

  testWidgets('statistics: empty year renders chart and empty states without overflow', (tester) async {
    final db = await _pumpApp(tester, const Size(390, 844));

    await tester.tap(find.text('Statistics'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Monthly spending'), findsOneWidget);
    // Readout of the selected (current) month.
    expect(find.textContaining(': \$0.00'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _dispose(tester, db);
  });
}
