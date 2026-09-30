import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/routes.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/finance/recurrence.dart';
import '../../../domain/finance/recurring_poster.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../application/recurring_providers.dart';

String frequencyLabel(RecurrenceRule rule) {
  if (rule.interval == 1) {
    return switch (rule.frequency) {
      Frequency.daily => 'Daily',
      Frequency.weekly => 'Weekly',
      Frequency.monthly => 'Monthly',
      Frequency.yearly => 'Yearly',
    };
  }
  final unit = switch (rule.frequency) {
    Frequency.daily => 'days',
    Frequency.weekly => 'weeks',
    Frequency.monthly => 'months',
    Frequency.yearly => 'years',
  };
  return 'Every ${rule.interval} $unit';
}

/// Subscriptions or recurring bills (rent, electricity, gym…), by [kind].
class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key, required this.kind});

  final RecurringKind kind;

  bool get _isSubscription => kind == RecurringKind.subscription;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(recurringItemsProvider);
    final currency = ref.watch(currencyProvider);
    final today = ref.watch(clockProvider)();
    final categories = ref.watch(categoryByIdProvider);
    final dateFormat = DateFormat.MMMd();

    return Scaffold(
      appBar: AppBar(title: Text(_isSubscription ? 'Subscriptions' : 'Recurring expenses')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => context.push(Routes.newRecurringOfKind(kind.name)),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
      ),
      body: all.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(
          child: EmptyState(icon: Icons.error_outline_rounded, message: 'Could not load data.'),
        ),
        data: (allItems) {
          final items = allItems.where((i) => i.kind == kind).toList()
            ..sort((a, b) {
              // Active first, then by next charge.
              final da = a.nextDueDate(today), db = b.nextDueDate(today);
              if (da == null || db == null) return da == null ? (db == null ? 0 : 1) : -1;
              return da.compareTo(db);
            });
          final totals = RecurringPoster.totals(items, currency, kind: kind);

          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Breakpoints.expanded),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  Card(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Wrap(
                        spacing: 32,
                        runSpacing: 12,
                        children: [
                          _Figure(label: 'Per month', value: totals.monthly.format()),
                          _Figure(label: 'Per year', value: totals.yearly.format()),
                          _Figure(label: 'Active', value: '${totals.count}'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Charges are recorded as expenses automatically on their due date.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  if (items.isEmpty)
                    EmptyState(
                      icon: _isSubscription ? Icons.autorenew_rounded : Icons.event_repeat_rounded,
                      message: _isSubscription
                          ? 'No subscriptions yet. Add streaming, apps or memberships.'
                          : 'No recurring expenses yet. Add rent, utilities, insurance, loans…',
                    ),
                  for (final item in items)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      onTap: () => context.push(Routes.editRecurring(item.id)),
                      leading: Icon(
                        iconForKey(categories[item.categoryId]?.iconKey ?? (_isSubscription ? 'subscriptions' : 'bills')),
                        color: item.isActive ? null : Theme.of(context).disabledColor,
                      ),
                      title: Text(item.name, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        [
                          '${item.amount.format()} · ${frequencyLabel(item.rule)}',
                          if (item.nextDueDate(today) case final next?)
                            'Next: ${dateFormat.format(next)}'
                          else
                            item.isActive ? 'Ended' : 'Paused',
                        ].join('\n'),
                      ),
                      isThreeLine: true,
                      trailing: Switch(
                        value: item.isActive,
                        onChanged: (active) =>
                            ref.read(recurringActionsProvider).save(item.copyWith(isActive: active)),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSecondaryContainer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
        Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
