# Expense Manager — Architecture

Offline-first personal finance app for Android and iOS, built with Flutter + Material 3.
This document records the seven decisions made before coding. Update it whenever one changes.

---

## 1. Architecture

Layered, feature-first. Dependencies only point **inward** (presentation → application → domain ← data).

```text
lib/
├── main.dart                 Entry point: bootstrap DB, run ProviderScope
├── app/                      App shell: MaterialApp.router, go_router config, adaptive nav shell
├── core/                     Framework-agnostic building blocks (no Flutter widgets except theme/layout)
│   ├── money/                Money value type, Currency, safe parsing/formatting
│   ├── time/                 YearMonth, date helpers
│   ├── theme/                Material 3 light/dark themes, design tokens
│   └── layout/               Breakpoints for responsive layouts
├── domain/                   Pure Dart — the heart of the app. No Flutter, no Drift.
│   ├── entities/             Immutable business models (FinanceTransaction, Category, Budget …)
│   ├── repositories/         Abstract repository contracts
│   ├── finance/              CENTRALIZED financial calculations (budgets, recurrence, summaries, stats)
│   └── insights/             Rule-based recommendations behind an InsightsEngine interface
├── data/                     Implementations of domain contracts
│   ├── database/             Drift (SQLite) schema, migrations, seeding
│   └── repositories/         Drift-backed repositories (map DB rows ⇄ domain entities)
├── features/<feature>/       One folder per feature
│   ├── application/          Riverpod providers / notifiers (state + use-case orchestration)
│   └── presentation/         Screens and feature widgets (UI only)
└── shared/
    ├── providers/            DI wiring: database + repository providers
    └── widgets/              Reusable UI components
```

Rules

- Widgets never contain business logic or call the database. They read providers.
- All money math lives in `domain/finance` and `core/money`. Nothing else adds/divides amounts.
- Domain entities are separate from Drift rows (`*Record`). Swapping SQLite for a cloud source only touches `data/`.
- Every external concern (storage, backup target, insights, auth, notifications) is behind an interface so a
  cloud/AI implementation can replace the local one via a provider override.

## 2. Database — entities and relationships

Engine: **SQLite via Drift** (type-safe queries, reactive streams, versioned migrations, in-memory testing).

Conventions on every syncable table:

| Column | Purpose |
|---|---|
| `id TEXT PK` | UUID v4 (defaults use stable IDs like `cat_food`, so two devices never duplicate them) |
| `created_at`, `updated_at` | Audit + last-write-wins sync later |
| `deleted_at` (nullable) | Soft delete → deletions can be synced |

Money is stored as **`INTEGER` minor units** (cents) + ISO currency code. Never `double`.

```text
profiles            id, name, email, avatar_path, country_code, currency_code
categories          id, name, icon_key, color, kind(expense|income|both), is_default, sort_order, archived
payment_methods     id, name, type(cash|debitCard|creditCard|bankTransfer|digitalWallet|other), icon_key, is_default, archived
transactions        id, type(expense|income|transfer|savings), amount_minor, currency_code, description,
                    category_id → categories, payment_method_id → payment_methods,
                    recurring_item_id → recurring_items, savings_goal_id → savings_goals,
                    source (income), notes, occurred_at
budgets             id, category_id → categories (NULL = global monthly budget), amount_minor, currency_code,
                    start_month (yyyymm), end_month (yyyymm, NULL = open-ended)
recurring_items     id, kind(subscription|bill), name, amount_minor, currency_code,
                    frequency(daily|weekly|monthly|yearly), interval (custom = interval > 1),
                    anchor_date, end_date, posted_from, category_id, payment_method_id, is_active, notes
savings_goals       id, name, target_minor, currency_code, target_date, color, icon_key, archived
                    (saved amount is DERIVED from `transactions` of type savings → single source of truth)
app_settings        key PK, value            (theme, backup frequency, lock flags …)
backup_records      id, file_name, location(local|cloud), size_bytes, sha256, schema_version, trigger, status, created_at
```

Subscriptions and recurring expenses share one table (`recurring_items.kind`) because they share scheduling
and cost math; the UI presents them as two features.

Auto-posting: due occurrences become expense transactions with deterministic IDs (`<itemId>_<yyyymmdd>`) inserted
with `INSERT OR IGNORE`, so re-running is harmless and a generated expense the user deleted is never re-created.
`posted_from` is set when an item is resumed or its schedule changes, so paused periods are not charged and the
old schedule's dates are not charged twice. Back-fill is limited to one year.

Budgets are versioned by month range: changing a budget closes the current row (`end_month`) and opens a new one,
so historical months keep the budget that applied at the time.

## 3. Navigation

`go_router` with a `StatefulShellRoute.indexedStack` (each tab keeps its own stack & scroll position).

| Tab | Route | Contains |
|---|---|---|
| Home | `/` | Dashboard |
| Transactions | `/transactions` | History, search/filter, add/edit expense & income |
| Budgets | `/budgets` | Global + category budgets |
| Statistics | `/statistics` | Charts, year selector |
| More | `/more` | Subscriptions, recurring, savings, categories, profile, settings, backup |

Adaptive shell: `NavigationBar` on phones (< 600 dp), `NavigationRail` on tablets/landscape, extended rail ≥ 1200 dp.
Deep-linkable routes make a future web dashboard straightforward.

## 4. State management

**Riverpod** (`flutter_riverpod`, no code generation).

- `shared/providers`: `appDatabaseProvider` → repository providers (overridable in tests / for cloud impls).
- Feature `application/` layer: `StreamProvider`s built on Drift `watch()` queries → UI updates automatically
  when data changes anywhere; `Notifier`s for editable state (theme, forms, filters).
- Derived data (dashboard summary, budget progress) is computed by domain calculators inside providers.

## 5. Backup strategy

- Format: one JSON document `{ format, schemaVersion, appVersion, createdAt, sha256, data: { table: [rows] } }`.
  `sha256` = hash of the canonical `data` bytes. It detects corruption only, not tampering.
- **Manual backup** → app *Application Support* `/backups` (not Documents, so it stays out of the iOS Files app), recorded in `backup_records`.
- **Automatic backup** (daily/weekly/monthly): checked on app start/resume, with retention/rotation. WorkManager/BGTask later.
- **Restore treats the file as untrusted input:**
  - size cap (50 MB) and parsing in an isolate;
  - table and column names mapped to a fixed allow-list (names from the file never reach SQL);
  - every row goes through the same domain validators as the repositories;
  - older schemas upgraded by versioned JSON migrations;
  - single DB transaction with `PRAGMA defer_foreign_keys = ON`, then `foreign_key_check` before commit;
  - a safety backup is taken first.
- **Never backed up or restored:** security state (PIN hash, lock flags) and `backup_records`.
- **Export**: passphrase-encrypted by default when leaving the sandbox (AES-256-GCM, Argon2id key). CSV export escapes
  cells starting with `= + - @` (CSV injection).
- `BackupStorage` interface → `LocalBackupStorage` now, `CloudBackupStorage` (Drive/iCloud/Firebase) later.
- File names are generated by the app, base name only, no path separators.

## 6. Security strategy

- **PIN:**
  - hash + failed-attempt counter stored in `flutter_secure_storage`, never in SQLite;
  - Argon2id (≈19–64 MiB, t=2–3) or PBKDF2-HMAC-SHA256 ≥ 600k iterations via `cryptography_flutter`;
  - 16-byte `Random.secure()` salt, constant-time compare, 6+ digits allowed;
  - exponential lockout, because a short PIN can always be brute-forced offline.
- **Lock state:** the app is locked whenever a PIN hash exists in secure storage. It is never read from the database.
- **Secure storage:**
  - iOS `first_unlock_this_device`;
  - stale Keychain entries wiped on first launch after a reinstall.
- **Biometrics:** `local_auth` (Face ID / fingerprint) with the PIN as fallback.
  - Android needs `FlutterFragmentActivity`.
  - Biometric-bound keys use `BiometryCurrentSet`, so re-enrolling biometrics invalidates them.
- **App lock placement:** the lock gate sits above the router, so no screen or deep link renders before unlock.
- **Platform settings:**
  - `android:allowBackup="false"` (or exclude the database and secure prefs through `dataExtractionRules`);
  - `FLAG_SECURE` on Android and a privacy cover on iOS when the app is inactive, so balances don't show in the app switcher;
  - notifications use private visibility and generic text.
- **Database encryption:** SQLCipher (random 256-bit key in secure storage). Decide before the public release, because migrating
  an existing plaintext database is risky.
- **Data hygiene:**
  - error messages never contain user data;
  - no logging of amounts or notes;
  - soft-deleted rows are purged after N days.
- **Input limits:**
  - amounts are capped at `Money.maxMinor`;
  - text lengths are capped in the repositories;
  - search uses bound `LIKE` with escaping, and sort options come from a fixed enum.
- No analytics or network calls in the MVP, so no data leaves the device.

## 7. Phases

| Phase | Scope | Status |
|---|---|---|
| **0 – Foundation** | Architecture, Money type, Drift schema + seeding, repositories, calculators, rule-based insights, themes, adaptive navigation shell, dashboard wired to data, theme settings, tests | ✅ |
| **1 – Core MVP** | Add/edit/delete expense & income (undo), categories & payment methods (custom, archive), history with search / type / category / date / amount filters and sorting | ✅ |
| **2 – Planning** | Monthly + category budgets (versioned per month, allocation), recurring expenses & subscriptions (custom frequencies, pause, monthly/yearly cost), idempotent auto-posting of due charges | ✅ |
| **3 – Insight** | Statistics: monthly bars per year (tap a month), month-vs-previous comparison by category, spending by category, highlights (top category / day / month), annual total, monthly average, yearly history, year selector. Charts are plain Flutter widgets (no chart dependency) | ✅ |
| **4 – Profile & data** | Profile (name, email, photo, country, currency). Backups: manual + automatic (daily/weekly/monthly, checked on launch, last 10 kept), validation (format, version, checksum, typed rows, DB constraints), all-or-nothing restore with safety copy, restore from file, export via share sheet | ✅ MVP complete |
| 5 – Post-MVP | Savings goals UI, local notifications, CSV/JSON export, PIN/biometric lock, encrypted backup export | next |
| 6 – Cloud | Auth (Google/Apple), sync, cloud backup, premium, multi-account, AI assistant, OCR, bank import | |

Verification after each phase: `flutter analyze`, `flutter test`, manual run on a phone + tablet size,
light/dark check, and DB migration test when `schemaVersion` changes.
