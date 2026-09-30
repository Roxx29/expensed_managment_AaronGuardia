/// Enum names are persisted as text in the database — never rename a value
/// without a migration.
library;

enum TransactionType { expense, income, transfer, savings }

enum CategoryKind { expense, income, both }

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
