// Home quick-add buttons. Uses an in-memory database, so it carries the `db` tag.
@Tags(['db'])
library;

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:expense_manager/app/app.dart';
import 'package:expense_manager/data/database/app_database.dart';
import 'package:expense_manager/domain/entities/entities.dart';
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
  testWidgets('Income quick button opens the form as income and saves it to Home', (tester) async {
    final db = await _pumpApp(tester, const Size(390, 844));

    // FilledButton.tonalIcon builds a private FilledButton subclass, so match by `is`.
    await tester.tap(find.ancestor(of: find.text('Income'), matching: find.byWidgetPredicate((w) => w is FilledButton)));
    await tester.pumpAndSettle();

    final segments = tester.widget<SegmentedButton<TransactionType>>(find.byType(SegmentedButton<TransactionType>));
    expect(segments.selected, {TransactionType.income});

    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '1000');
    // Income labels the description as optional.
    await tester.enterText(find.widgetWithText(TextFormField, 'Description (optional)'), 'Salary');
    // The income form has an extra Source field; make sure Save is on screen.
    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.byType(SegmentedButton<TransactionType>), findsNothing); // form closed
    expect(find.text('Available money'), findsOneWidget); // back on Home
    expect(find.text('Salary'), findsOneWidget);
    expect(find.text('+\$1,000.00'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _dispose(tester, db);
  });
}
