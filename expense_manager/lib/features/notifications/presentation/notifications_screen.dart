import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../domain/finance/budget_calculator.dart';
import '../../../domain/notifications/reminder_planner.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../application/notification_providers.dart';
import '../application/notification_service.dart';

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
    final days = ReminderPlanner.parseDays(setting(NotificationKeys.reminderTiming));
    final hour = ReminderPlanner.parseHour(setting(NotificationKeys.reminderHour));
    final sound = NotificationSounds.parse(setting(NotificationKeys.sound));
    final actions = ref.read(notificationActionsProvider);
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
                    Text(context.tr('Remind me'), style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 8),
                    // Several at once, e.g. a week before and the same day.
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final d in ReminderPlanner.dayOptions)
                          FilterChip(
                            label: Text(switch (d) {
                              0 => context.tr('Same day'),
                              1 => context.tr('Day before'),
                              7 => context.tr('1 week before'),
                              _ => context.tr('{days} days before', {'days': d}),
                            }),
                            selected: days.contains(d),
                            // At least one stays selected.
                            onSelected: !reminders || (days.length == 1 && days.contains(d))
                                ? null
                                : (on) => actions.setDays(on ? {...days, d} : ({...days}..remove(d))),
                          ),
                      ],
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      enabled: reminders,
                      leading: const Icon(Icons.schedule_rounded),
                      title: Text(context.tr('Reminder time')),
                      trailing: Text(TimeOfDay(hour: hour, minute: 0).format(context)),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay(hour: hour, minute: 0),
                        );
                        // ponytail: whole hours only; add minutes when someone asks.
                        if (picked != null) await actions.setHour(picked.hour);
                      },
                    ),
                    Text(
                      context.tr('For your subscriptions and bills. Covers the next 30 days and updates each time you open the app.'),
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
              SectionCard(
                title: context.tr('Notification sound'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    RadioGroup<String>(
                      groupValue: sound,
                      onChanged: (s) {
                        if (s != null) actions.setSound(s);
                      },
                      child: Column(
                        children: [
                          for (final s in NotificationSounds.all)
                            RadioListTile<String>(
                              contentPadding: EdgeInsets.zero,
                              value: s,
                              title: Text(switch (s) {
                                NotificationSounds.system => context.tr('Phone default'),
                                NotificationSounds.silent => context.tr('Silent'),
                                'monchi_coin' => context.tr('Coin'),
                                'monchi_bell' => context.tr('Bell'),
                                _ => context.tr('Chime'),
                              }),
                            ),
                        ],
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(context.tr('Test sound')),
                        onPressed: () async {
                          const title = 'Monchi';
                          final body = context.tr('This is how your reminders will sound');
                          final channel = context.tr('Payment reminders');
                          if (await ref.read(notificationServiceProvider).requestPermission()) {
                            await actions.testSound(sound, title: title, body: body, channelName: channel);
                          }
                        },
                      ),
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
