// ignore_for_file: recursive_getters
import 'package:drift/drift.dart';

import '../../domain/entities/enums.dart';

/// Columns shared by every syncable table: UUID key, audit timestamps and a
/// soft-delete marker so deletions can be synchronized later.
mixin SyncColumns on Table {
  TextColumn get id => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ProfileRecord')
class Profiles extends Table with SyncColumns {
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get email => text().nullable()();
  TextColumn get avatarPath => text().nullable()();
  TextColumn get countryCode => text().withLength(min: 2, max: 2).nullable()();
  TextColumn get currencyCode => text().withLength(min: 3, max: 3)();
}

@DataClassName('CategoryRecord')
class Categories extends Table with SyncColumns {
  TextColumn get name => text().withLength(min: 1, max: 50)();
  TextColumn get iconKey => text()();
  IntColumn get color => integer()();
  TextColumn get kind => textEnum<CategoryKind>()();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}

@DataClassName('PaymentMethodRecord')
class PaymentMethods extends Table with SyncColumns {
  TextColumn get name => text().withLength(min: 1, max: 50)();
  TextColumn get type => textEnum<PaymentMethodType>()();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}

@DataClassName('RecurringItemRecord')
class RecurringItems extends Table with SyncColumns {
  TextColumn get kind => textEnum<RecurringKind>()();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  IntColumn get amountMinor =>
      integer().check(amountMinor.isBiggerThanValue(0))();
  TextColumn get currencyCode => text().withLength(min: 3, max: 3)();
  TextColumn get frequency => textEnum<Frequency>()();
  IntColumn get interval => integer()
      .withDefault(const Constant(1))
      .check(interval.isBiggerThanValue(0))();
  DateTimeColumn get anchorDate => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()();

  /// Charges before this date are never auto-posted (set on resume or when
  /// the schedule changes, so paused/old periods are not charged).
  DateTimeColumn get postedFrom => dateTime().nullable()();
  TextColumn get categoryId =>
      text().nullable().references(Categories, #id)();
  TextColumn get paymentMethodId =>
      text().nullable().references(PaymentMethods, #id)();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get notes => text().nullable()();
}

@DataClassName('SavingsGoalRecord')
class SavingsGoals extends Table with SyncColumns {
  TextColumn get name => text().withLength(min: 1, max: 80)();
  IntColumn get targetMinor =>
      integer().check(targetMinor.isBiggerThanValue(0))();
  TextColumn get currencyCode => text().withLength(min: 3, max: 3)();
  DateTimeColumn get targetDate => dateTime().nullable()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}

@DataClassName('TransactionRecord')
@TableIndex(name: 'idx_transactions_occurred_at', columns: {#occurredAt})
@TableIndex(name: 'idx_transactions_category', columns: {#categoryId})
class Transactions extends Table with SyncColumns {
  TextColumn get type => textEnum<TransactionType>()();

  /// Always positive; [type] carries the direction.
  IntColumn get amountMinor =>
      integer().check(amountMinor.isBiggerThanValue(0))();
  TextColumn get currencyCode => text().withLength(min: 3, max: 3)();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get categoryId =>
      text().nullable().references(Categories, #id)();
  TextColumn get paymentMethodId =>
      text().nullable().references(PaymentMethods, #id)();
  TextColumn get recurringItemId =>
      text().nullable().references(RecurringItems, #id)();
  TextColumn get savingsGoalId =>
      text().nullable().references(SavingsGoals, #id)();
  TextColumn get source => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();

  /// Project or client (schema v2); null = personal.
  TextColumn get project => text().nullable()();

  /// Shared wallet (schema v3); null = personal. No foreign key: a wallet's
  /// rows can arrive before the wallet itself during a sync.
  TextColumn get walletId => text().nullable()();

  /// Firebase uid of who recorded it (schema v3), for shared wallets.
  TextColumn get createdBy => text().nullable()();
}

/// Shared wallets (schema v3), see claude/WALLETS.md.
@DataClassName('WalletRecord')
class Wallets extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get kind => textEnum<WalletKind>()();

  /// base64url AES-256 key of the wallet's encrypted cloud copy.
  TextColumn get secret => text()();
  TextColumn get ownerUid => text().nullable()();
}

/// Budgets are versioned by month range (yyyymm). `categoryId == null` is the
/// global budget.
@DataClassName('BudgetRecord')
class Budgets extends Table with SyncColumns {
  TextColumn get categoryId =>
      text().nullable().references(Categories, #id)();
  IntColumn get amountMinor =>
      integer().check(amountMinor.isBiggerOrEqualValue(0))();
  TextColumn get currencyCode => text().withLength(min: 3, max: 3)();
  IntColumn get startMonth => integer()();
  IntColumn get endMonth => integer().nullable()();
}

/// Key/value app settings (theme, backup frequency, lock flags …).
@DataClassName('SettingRecord')
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DataClassName('BackupRecord')
class BackupRecords extends Table {
  TextColumn get id => text()();
  TextColumn get fileName => text()();
  TextColumn get location => text()(); // local | cloud
  IntColumn get sizeBytes => integer()();
  TextColumn get sha256 => text()();
  IntColumn get schemaVersion => integer()();
  TextColumn get origin => text()(); // manual | automatic
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
