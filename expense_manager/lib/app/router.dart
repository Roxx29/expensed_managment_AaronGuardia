import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/l10n/l10n.dart';
import '../domain/entities/entities.dart';
import '../features/backup/presentation/backup_screen.dart';
import '../features/assistant/presentation/assistant_screen.dart';
import '../features/budgets/presentation/budgets_screen.dart';
import '../features/categories/presentation/categories_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/import/presentation/import_screen.dart';
import '../features/notifications/presentation/notifications_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/recurring/presentation/recurring_form_screen.dart';
import '../features/recurring/presentation/recurring_screen.dart';
import '../features/savings/presentation/savings_screen.dart';
import '../features/security/presentation/security_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/statistics/presentation/statistics_screen.dart';
import '../features/transactions/presentation/transaction_form_screen.dart';
import '../features/transactions/presentation/transactions_screen.dart';
import 'adaptive_shell.dart';
import 'more_screen.dart';
import 'routes.dart';

/// Provided (not global) so each ProviderScope — e.g. each test — gets a fresh
/// navigation state. Auth/app-lock redirects will hook in here later.
final routerProvider = Provider<GoRouter>((ref) {
  final router = _buildRouter();
  ref.onDispose(router.dispose);
  return router;
});

GoRouter _buildRouter() => GoRouter(
  initialLocation: Routes.dashboard,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AdaptiveShell(navigationShell: shell, location: state.uri.path),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: Routes.dashboard, builder: (_, _) => const DashboardScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: Routes.transactions, builder: (_, _) => const TransactionsScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: Routes.budgets, builder: (_, _) => const BudgetsScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: Routes.more,
            builder: (_, _) => const MoreScreen(),
            routes: [
              GoRoute(path: 'statistics', builder: (_, _) => const StatisticsScreen()),
              GoRoute(path: 'settings', builder: (_, _) => const SettingsScreen()),
              GoRoute(
                path: 'subscriptions',
                builder: (_, _) => const RecurringScreen(kind: RecurringKind.subscription),
              ),
              GoRoute(
                path: 'recurring',
                builder: (_, _) => const RecurringScreen(kind: RecurringKind.bill),
              ),
              GoRoute(path: 'categories', builder: (_, _) => const CategoriesScreen()),
              GoRoute(path: 'profile', builder: (_, _) => const ProfileScreen()),
              GoRoute(path: 'backup', builder: (_, _) => const BackupScreen()),
              GoRoute(path: 'savings', builder: (_, _) => const SavingsScreen()),
              GoRoute(path: 'security', builder: (_, _) => const SecurityScreen()),
              GoRoute(path: 'notifications', builder: (_, _) => const NotificationsScreen()),
              GoRoute(path: 'import', builder: (_, _) => const ImportScreen()),
              GoRoute(path: 'assistant', builder: (_, _) => const AssistantScreen()),
            ],
          ),
        ]),
      ],
    ),
    // `new` is matched before `:id` because routes are checked in order.
    GoRoute(
      path: Routes.newTransaction,
      builder: (_, state) => TransactionFormScreen(
        initialType: TransactionType.values.asNameMap()[state.uri.queryParameters['type']] ??
            TransactionType.expense,
        draft: state.extra is TransactionDraft ? state.extra! as TransactionDraft : null,
      ),
    ),
    GoRoute(
      path: '/transaction/:id',
      builder: (_, state) => TransactionFormScreen(transactionId: state.pathParameters['id']),
    ),
    GoRoute(
      path: Routes.newRecurring,
      builder: (_, state) => RecurringFormScreen(
        kind: RecurringKind.values.asNameMap()[state.uri.queryParameters['kind']] ?? RecurringKind.bill,
      ),
    ),
    GoRoute(
      path: '/recurring/:id',
      builder: (_, state) => RecurringFormScreen(itemId: state.pathParameters['id']),
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    body: Center(child: Text(context.tr('Page not found'))),
  ),
);
