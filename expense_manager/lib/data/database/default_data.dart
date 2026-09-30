import '../../domain/entities/entities.dart';

/// Default categories and payment methods created on first launch.
/// Stable IDs (`cat_food`) prevent duplicates when multiple devices sync.
const defaultCategories = <FinanceCategory>[
  FinanceCategory(id: 'cat_food', name: 'Food', iconKey: 'food', color: 0xFFEF6C00, kind: CategoryKind.expense, isDefault: true, sortOrder: 0),
  FinanceCategory(id: 'cat_gas', name: 'Gas', iconKey: 'gas', color: 0xFF6D4C41, kind: CategoryKind.expense, isDefault: true, sortOrder: 1),
  FinanceCategory(id: 'cat_transportation', name: 'Transportation', iconKey: 'transportation', color: 0xFF1E88E5, kind: CategoryKind.expense, isDefault: true, sortOrder: 2),
  FinanceCategory(id: 'cat_clothing', name: 'Clothing', iconKey: 'clothing', color: 0xFFD81B60, kind: CategoryKind.expense, isDefault: true, sortOrder: 3),
  FinanceCategory(id: 'cat_entertainment', name: 'Entertainment', iconKey: 'entertainment', color: 0xFF8E24AA, kind: CategoryKind.expense, isDefault: true, sortOrder: 4),
  FinanceCategory(id: 'cat_health', name: 'Health', iconKey: 'health', color: 0xFFE53935, kind: CategoryKind.expense, isDefault: true, sortOrder: 5),
  FinanceCategory(id: 'cat_education', name: 'Education', iconKey: 'education', color: 0xFF3949AB, kind: CategoryKind.expense, isDefault: true, sortOrder: 6),
  FinanceCategory(id: 'cat_home', name: 'Home', iconKey: 'home', color: 0xFF00897B, kind: CategoryKind.expense, isDefault: true, sortOrder: 7),
  FinanceCategory(id: 'cat_technology', name: 'Technology', iconKey: 'technology', color: 0xFF546E7A, kind: CategoryKind.expense, isDefault: true, sortOrder: 8),
  FinanceCategory(id: 'cat_shopping', name: 'Shopping', iconKey: 'shopping', color: 0xFFF4511E, kind: CategoryKind.expense, isDefault: true, sortOrder: 9),
  FinanceCategory(id: 'cat_subscriptions', name: 'Subscriptions', iconKey: 'subscriptions', color: 0xFF5E35B1, kind: CategoryKind.expense, isDefault: true, sortOrder: 10),
  FinanceCategory(id: 'cat_other', name: 'Other', iconKey: 'other', color: 0xFF757575, kind: CategoryKind.both, isDefault: true, sortOrder: 11),
  FinanceCategory(id: 'cat_salary', name: 'Salary', iconKey: 'salary', color: 0xFF2E7D32, kind: CategoryKind.income, isDefault: true, sortOrder: 12),
];

const defaultPaymentMethods = <PaymentMethod>[
  PaymentMethod(id: 'pm_cash', name: 'Cash', type: PaymentMethodType.cash, isDefault: true),
  PaymentMethod(id: 'pm_debit', name: 'Debit card', type: PaymentMethodType.debitCard, isDefault: true),
  PaymentMethod(id: 'pm_credit', name: 'Credit card', type: PaymentMethodType.creditCard, isDefault: true),
  PaymentMethod(id: 'pm_transfer', name: 'Bank transfer', type: PaymentMethodType.bankTransfer, isDefault: true),
];

const localProfileId = 'local_profile';
