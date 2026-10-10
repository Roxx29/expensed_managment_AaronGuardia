/// Route paths. Kept apart from the router so features can link without
/// importing screens.
abstract final class Routes {
  static const dashboard = '/';
  static const transactions = '/transactions';
  static const budgets = '/budgets';
  static const statistics = '/more/statistics';
  static const more = '/more';
  static const settings = '/more/settings';
  static const subscriptions = '/more/subscriptions';
  static const recurring = '/more/recurring';
  static const savings = '/more/savings';
  static const categories = '/more/categories';
  static const profile = '/more/profile';
  static const backup = '/more/backup';
  static const security = '/more/security';
  static const notifications = '/more/notifications';
  static const importStatement = '/more/import';
  static const assistant = '/more/assistant';
  static const wallets = '/more/wallets';
  static const report = '/more/report';

  // Full-screen routes (outside the tab shell).
  static const premium = '/premium';
  static const welcome = '/welcome';
  static const newTransaction = '/transaction/new';
  static String editTransaction(String id) => '/transaction/$id';
  static String newWalletTransaction(String walletId) => '$newTransaction?wallet=$walletId';
  static String wallet(String id) => '/wallet/$id';
  static const newRecurring = '/recurring/new';
  static String newRecurringOfKind(String kind) => '$newRecurring?kind=$kind';
  static String editRecurring(String id) => '/recurring/$id';
}
