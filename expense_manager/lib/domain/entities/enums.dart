/// Enum names are persisted as text in the database — never rename a value
/// without a migration.
library;

/// `savings` moves money into a savings goal, `savingsWithdrawal` takes it
/// back out (amounts are always positive; the type carries the direction).
enum TransactionType { expense, income, transfer, savings, savingsWithdrawal }

enum CategoryKind { expense, income, both }

/// Shared wallets (Carteras): a business, a family or anything else.
enum WalletKind { business, family, other }

enum PaymentMethodType {
  cash,
  debitCard,
  creditCard,
  bankTransfer,
  digitalWallet,
  other,
}

/// Subscriptions and bills share scheduling; the UI shows them separately.
enum RecurringKind { subscription, bill }

/// Base unit of a recurrence. "Custom" = any unit with `interval > 1`.
enum Frequency { daily, weekly, monthly, yearly }
