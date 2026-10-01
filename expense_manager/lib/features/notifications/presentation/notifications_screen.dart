import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../domain/finance/budget_calculator.dart';
import '../../../domain/notifications/reminder_planner.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../application/notification_providers.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  Future<void> _toggle(BuildContext context, WidgetRef ref, String key, bool on) async {
    // Resolved before the await: the screen may be gone afterwards.
    final messenger = ScaffoldMessenger.of(context);
    final deniedText = context.tr('Notifications are blocked. Allow them in your device settings.');
    final ok = await ref.read(notificationActionsProvider).setEnabled(key, on);
    if (!ok) messenger.showSnackBar(SnackBar(content: Text(deniedText)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String? setting(String key) => ref.watch(notificationSettingProvider(key)).value;
    final reminders = setting(NotificationKeys.reminders) == 'on';
    final timing = parseTiming(setting(NotificationKeys.reminderTiming));
    final budgetAlerts = setting(NotificationKeys.budgetAlerts) == 'on';
    final small = Theme.of(context).textTheme.bodySmall;

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Notifications'))),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Breakpoints.expanded),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SectionCard(
                title: context.tr('Payment reminders'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.notifications_active_rounded),
                      title: Text(context.tr('Remind me of upcoming payments')),
                      value: reminders,
                      onChanged: (on) => _toggle(context, ref, NotificationKeys.reminders, on),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<ReminderTiming>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(value: ReminderTiming.dayBefore, label: Text(context.tr('Day before'))),
                        ButtonSegment(value: ReminderTiming.sameDay, label: Text(context.tr('Same day'))),
                      ],
                      selected: {timing},
                      onSelectionChanged:
                          reminders ? (s) => ref.read(notificationActionsProvider).setTiming(s.first) : null,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.tr(
                        'For your subscriptions and bills, at 9:00 AM. Covers the next 30 days and updates each time you open the app.',
                      ),
                      style: small,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: context.tr('Budget alerts'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.savings_rounded),
                      title: Text(context.tr('Alert me about my budgets')),
                      value: budgetAlerts,
                      onChanged: (on) => _toggle(context, ref, NotificationKeys.budgetAlerts, on),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.tr(
                        'Once when you reach {percent}% of a monthly budget and once if you go over it.',
                        {'percent': (BudgetCalculator.warningThreshold * 100).round()},
                      ),
                      style: small,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                context.tr('For your privacy, notifications never show amounts.'),
                style: small,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
