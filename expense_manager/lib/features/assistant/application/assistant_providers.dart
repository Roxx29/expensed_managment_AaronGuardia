import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/assistant/assistant.dart';
import '../../../shared/providers/providers.dart';
import '../../dashboard/application/dashboard_providers.dart';

/// Swap for an LLM-backed assistant later via a provider override.
final financeAssistantProvider = Provider<FinanceAssistant>((ref) => const RuleBasedAssistant());

/// The data the assistant answers from, kept up to date with the database.
final assistantContextProvider = FutureProvider<AssistantContext>((ref) async {
  // Watch all sources before awaiting so every dependency is registered.
  final transactions = ref.watch(allTransactionsProvider.future);
  final recurring = ref.watch(recurringItemsProvider.future);
  final dashboard = ref.watch(dashboardProvider.future);
  final categories = ref.watch(categoryByIdProvider);
  final currency = ref.watch(currencyProvider);
  final today = ref.watch(clockProvider)();
  return AssistantContext(
    transactions: await transactions,
    categories: categories,
    recurringItems: await recurring,
    dashboard: await dashboard,
    currency: currency,
    today: today,
  );
});
