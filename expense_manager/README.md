# Expense Manager

Offline-first personal finance app built with Flutter and Material 3 for Android and iOS.
The architecture and the phase plan are in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Set up (first time)

This project has the Dart code only. The Android/iOS folders are generated for your machine:

```bash
flutter create . --project-name expense_manager --org com.aguardia --platforms android,ios
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # generates app_database.g.dart
```

`flutter create .` only adds the files that are missing. It doesn't overwrite `lib/` or `test/`.

After generating the Android folder, add `android:allowBackup="false"` to the `<application>` tag in
`android/app/src/main/AndroidManifest.xml`. This keeps the unencrypted financial database out of Google auto-backup
(see Security in the architecture doc).

**iOS:** the profile photo uses the photo library. Add this to `ios/Runner/Info.plist`:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Choose a profile photo.</string>
```

## Checks to run after every change

```bash
flutter analyze
flutter test                 # all tests
flutter test -x db           # skip database tests if sqlite3 is not on the host (Windows)
flutter run
```

**Windows and the database tests:** the `db`-tagged tests use native SQLite. Put `sqlite3.dll`
(from sqlite.org → "Precompiled Binaries for Windows") on your `PATH`, or run them with `-x db`.
The app itself bundles SQLite on Android and iOS through `drift_flutter`.

## Rebuild generated code

Run this after changing `lib/data/database/tables.dart`:

```bash
dart run build_runner build --delete-conflicting-outputs
```

Then bump `AppDatabase.currentSchemaVersion` and add a migration step.

## Project layout

```text
lib/
├── app/          MaterialApp, go_router, adaptive navigation shell
├── core/         Money, Currency, YearMonth, theme, breakpoints, IDs
├── domain/       Entities, repository contracts, financial calculators, insights (pure Dart)
├── data/         Drift database, tables, seeding, repository implementations
├── features/     dashboard/, settings/ … (application = providers, presentation = UI)
└── shared/       Dependency providers and reusable widgets
```

## Test suite

| File | Covers |
|---|---|
| `test/core/money_test.dart` | Integer money math, rounding, parsing (`1.234,56`, `$ 7.05`, limits), formatting |
| `test/core/year_month_test.dart` | Month arithmetic, keys, leap years |
| `test/domain/recurrence_test.dart` | Daily/weekly/monthly/yearly/custom schedules, month-end clamping, monthly/yearly cost |
| `test/domain/finance_calculators_test.dart` | Budget progress & warnings, monthly budget report, month summary, available balance |
| `test/domain/insights_test.dart` | Rule-based recommendations |
| `test/domain/dashboard_test.dart` | Dashboard snapshot, upcoming charges, subscription totals |
| `test/domain/transaction_filter_test.dart` | History search, type/category/date/amount filters, sorting |
| `test/domain/recurring_poster_test.dart` | Auto-posting of due charges, pause/resume, budget allocation |
| `test/domain/statistics_calculator_test.dart` | Yearly/monthly totals, average, top category/day/month, history, year list, month comparison |
| `test/domain/backup_policy_test.dart` | Automatic backup schedule and retention |
| `test/data/backup_test.dart` *(db)* | Backup → restore round trip, safety copy, rejected files (not a backup, newer version, edited, invalid rows), no security settings exported, automatic backups |
| `test/data/repositories_test.dart` *(db)* | Seeding, CRUD, soft delete + undo, idempotent auto-posting, versioned budgets, archiving, settings |
| `test/widget_test.dart` *(db)* | Phone/tablet navigation, theme switch, add-expense flow, amount validation, statistics screen |
