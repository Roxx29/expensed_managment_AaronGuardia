import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/l10n/l10n.dart';
import '../domain/entities/entities.dart';
import '../domain/usage/feature_counts.dart';
import '../features/backup/presentation/backup_screen.dart';
import '../features/assistant/presentation/assistant_screen.dart';
import '../features/budgets/presentation/budgets_screen.dart';
import '../features/categories/presentation/categories_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/import/presentation/import_screen.dart';
import '../features/notifications/presentation/notifications_screen.dart';
import '../features/onboarding/welcome_screen.dart';
import '../features/premium/application/usage_ping.dart';
import '../features/premium/presentation/paywall_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/recurring/presentation/recurring_form_screen.dart';
import '../features/recurring/presentation/recurring_screen.dart';
import '../features/savings/presentation/savings_screen.dart';
import '../features/security/presentation/security_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/statistics/presentation/statistics_screen.dart';
import '../features/reports/presentation/report_screen.dart';
import '../features/transactions/presentation/transaction_form_screen.dart';
import '../features/transactions/presentation/transactions_screen.dart';
import '../features/wallets/presentation/wallet_screen.dart';
import '../features/wallets/presentation/wallets_screen.dart';
import '../shared/widgets/motion.dart';
import 'adaptive_shell.dart';
import 'more_screen.dart';
import 'routes.dart';

/// Provided (not global) so each ProviderScope — e.g. each test — gets a fresh
/// navigation state. Auth/app-lock redirects will hook in here later.
final routerProvider = Provider<GoRouter>((ref) {
  final router = _buildRouter();
  // Screen opens per feature for the admin panel's "most used features".
  String? last;
  void onNavigate() {
    final feature = featureForPath(router.routerDelegate.currentConfiguration.uri.path);
    if (feature == null || feature == last) return;
    last = feature;
    ref.read(usageTrackerProvider).track(feature);
  }

  router.routerDelegate.addListener(onNavigate);
  ref.onDispose(() {
    router.routerDelegate.removeListener(onNavigate);
    router.dispose();
  });
  return router;
});

/// Full-screen forms, the paywall and welcome open as modals (fade + scale,
/// MonchiPageTransitionsBuilder in motion.dart).
Page<void> _modal(GoRouterState state, Widget child) =>
    MaterialPage(key: state.pageKey, name: modalPageName, child: child);

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
              // The first import is free (switching from another app); the
              // screen asks for Premium after that.
              GoRoute(path: 'import', builder: (_, _) => const ImportScreen()),
              GoRoute(path: 'wallets', builder: (_, _) => const WalletsScreen()),
              GoRoute(path: 'report', builder: (_, _) => const ReportScreen()),
              GoRoute(
                path: 'assistant',
                builder: (context, _) => PremiumGate(title: context.tr('Assistant'), child: const AssistantScreen()),
              ),
            ],
          ),
        ]),
      ],
    ),
    GoRoute(path: Routes.premium, pageBuilder: (_, state) => _modal(state, const PaywallScreen())),
    GoRoute(path: Routes.welcome, pageBuilder: (_, state) => _modal(state, const WelcomeScreen())),
    // `new` is matched before `:id` because routes are checked in order.
    GoRoute(
      path: Routes.newTransaction,
      pageBuilder: (_, state) => _modal(
        state,
        TransactionFormScreen(
          initialType: TransactionType.values.asNameMap()[state.uri.queryParameters['type']] ??
              TransactionType.expense,
          draft: state.extra is TransactionDraft ? state.extra! as TransactionDraft : null,
          walletId: state.uri.queryParameters['wallet'],
        ),
      ),
    ),
    GoRoute(path: '/wallet/:id', builder: (_, state) => WalletScreen(walletId: state.pathParameters['id']!)),
    GoRoute(
      path: '/transaction/:id',
      pageBuilder: (_, state) => _modal(state, TransactionFormScreen(transactionId: state.pathParameters['id'])),
    ),
    GoRoute(
      path: Routes.newRecurring,
      pageBuilder: (_, state) => _modal(
        state,
        RecurringFormScreen(
          kind: RecurringKind.values.asNameMap()[state.uri.queryParameters['kind']] ?? RecurringKind.bill,
        ),
      ),
    ),
    GoRoute(
      path: '/recurring/:id',
      pageBuilder: (_, state) => _modal(state, RecurringFormScreen(itemId: state.pathParameters['id'])),
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    body: Center(child: Text(context.tr('Page not found'))),
  ),
);
