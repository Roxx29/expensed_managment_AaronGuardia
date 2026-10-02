import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/strings_es.dart';
import '../../../core/time/year_month.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/finance/budget_calculator.dart';
import '../../../domain/notifications/reminder_planner.dart';
import '../../../shared/providers/providers.dart';
import '../../settings/application/settings_providers.dart';
import 'notification_service.dart';

abstract final class NotificationKeys {
  static const reminders = 'notifications.reminders';
  static const reminderTiming = 'notifications.reminder_timing';
  static const reminderHour = 'notifications.reminder_hour';
  static const sound = 'notifications.sound';
  static const budgetAlerts = 'notifications.budget_alerts';
  static const budgetAlertsShown = 'notifications.budget_alerts_shown';
}

final notificationServiceProvider = Provider<NotificationService>((ref) => LocalNotificationService());

/// Raw string value of a setting (null when unset).
final notificationSettingProvider = StreamProvider.family<String?, String>(
  (ref, key) => ref.watch(settingsRepositoryProvider).watch(key),
);

final notificationActionsProvider = Provider<NotificationActions>(NotificationActions.new);

class NotificationActions {
  NotificationActions(this._ref);

  final Ref _ref;

  /// Turns [key] on/off. Returns false (and keeps it off) when the user
  /// denies the notification permission.
  Future<bool> setEnabled(String key, bool on) async {
    if (on && !await _ref.read(notificationServiceProvider).requestPermission()) return false;
    await _ref.read(settingsRepositoryProvider).write(key, on ? 'on' : 'off');
    return true;
  }

  Future<void> setDays(Set<int> days) => _ref
      .read(settingsRepositoryProvider)
      .write(NotificationKeys.reminderTiming, ReminderPlanner.encodeDays(days));

  Future<void> setHour(int hour) =>
      _ref.read(settingsRepositoryProvider).write(NotificationKeys.reminderHour, '$hour');

  Future<void> setSound(String sound) => _ref.read(settingsRepositoryProvider).write(NotificationKeys.sound, sound);

  /// Shows a sample notification with [sound] right away.
  Future<void> testSound(String sound, {required String title, required String body, required String channelName}) =>
      _ref.read(notificationServiceProvider).show(
            id: 3000,
            title: title,
            body: body,
            channelId: _reminderChannel,
            channelName: channelName,
            sound: sound,
          );
}

/// Watched by the app root: keeps payment reminders scheduled and shows
/// budget alerts. Never throws.
final notificationSyncProvider = Provider<void>((ref) {
  ref.watch(_reminderSyncProvider);
  ref.watch(_budgetAlertSyncProvider);
});

// --- Text outside a BuildContext ---------------------------------------------

String _language(String? setting) =>
    setting == 'en' || setting == 'es' ? setting! : PlatformDispatcher.instance.locale.languageCode;

String _tr(String lang, String en, [Map<String, String> args = const {}]) {
  var text = lang == 'es' ? (esStrings[en] ?? en) : en;
  for (final e in args.entries) {
    text = text.replaceAll('{${e.key}}', e.value);
  }
  return text;
}

// --- Payment reminders -------------------------------------------------------

const _reminderChannel = 'payment_reminders';
const _budgetChannel = 'budget_alerts';

final _reminderSyncProvider = FutureProvider<void>((ref) async {
  final service = ref.watch(notificationServiceProvider);
  final now = ref.watch(clockProvider)();
  try {
    final enabled = await ref.watch(notificationSettingProvider(NotificationKeys.reminders).future);
    // Never turned on: nothing to cancel, and the plugin is left untouched.
    if (enabled == null) return;
    // Always cancel first: the plan is rebuilt from scratch on every change.
    await service.cancelRange(ReminderPlanner.firstId, ReminderPlanner.lastId);
    if (enabled != 'on') return;
    final days = ReminderPlanner.parseDays(
      await ref.watch(notificationSettingProvider(NotificationKeys.reminderTiming).future),
    );
    final hour = ReminderPlanner.parseHour(
      await ref.watch(notificationSettingProvider(NotificationKeys.reminderHour).future),
    );
    final sound = NotificationSounds.parse(await ref.watch(notificationSettingProvider(NotificationKeys.sound).future));
    final lang = _language(await ref.watch(notificationSettingProvider(SettingKeys.language).future));
    final items = await ref.watch(recurringItemsProvider.future);
    for (final n in ReminderPlanner.plan(items: items, now: now, daysBefore: days, hour: hour)) {
      // A newer run (settings changed) has cancelled and is rescheduling.
      if (!ref.mounted) return;
      await service.schedule(
        id: n.id,
        title: _tr(lang, n.title),
        body: _tr(lang, n.body, n.args),
        when: n.when,
        channelId: _reminderChannel,
        channelName: _tr(lang, 'Payment reminders'),
        sound: sound,
      );
    }
  } on Object {
    // Plugin unavailable (tests) or provider rebuilt mid-way: next run fixes it.
  }
});

// --- Budget alerts -----------------------------------------------------------

final _currentMonthProvider = Provider<YearMonth>((ref) => YearMonth.fromDate(ref.watch(clockProvider)()));

final _currentMonthTransactionsProvider = StreamProvider<List<FinanceTransaction>>((ref) {
  final month = ref.watch(_currentMonthProvider);
  return ref.watch(transactionRepositoryProvider).watchBetween(month.start, month.endExclusive);
});

final _currentMonthBudgetsProvider = StreamProvider<List<Budget>>(
  (ref) => ref.watch(budgetRepositoryProvider).watchForMonth(ref.watch(_currentMonthProvider)),
);

final _budgetAlertSyncProvider = FutureProvider<void>((ref) async {
  final service = ref.watch(notificationServiceProvider);
  final settings = ref.watch(settingsRepositoryProvider);
  // Resolved before any await: a rebuild disposes this ref mid-run, and the
  // run must still show the alerts it already marked as shown.
  final categoryRepository = ref.watch(categoryRepositoryProvider);
  final month = ref.watch(_currentMonthProvider);
  final currency = ref.watch(currencyProvider);
  try {
    if (await ref.watch(notificationSettingProvider(NotificationKeys.budgetAlerts).future) != 'on') return;
    final lang = _language(await ref.watch(notificationSettingProvider(SettingKeys.language).future));
    final sound = NotificationSounds.parse(await ref.watch(notificationSettingProvider(NotificationKeys.sound).future));
    final report = BudgetCalculator.monthlyReport(
      budgets: await ref.watch(_currentMonthBudgetsProvider.future),
      transactions: await ref.watch(_currentMonthTransactionsProvider.future),
      month: month,
      currency: currency,
    );

    final shown = BudgetAlertPlanner.prune(_decode(await settings.read(NotificationKeys.budgetAlertsShown)), month);
    final alerts = BudgetAlertPlanner.newAlerts(report: report, month: month, shown: shown);
    if (alerts.isEmpty) return;
    // Remember first, so a rebuild racing with this run cannot alert twice.
    await settings.write(
      NotificationKeys.budgetAlertsShown,
      jsonEncode([...shown, for (final a in alerts) a.key]),
    );

    final categories = {
      for (final c in await categoryRepository.watchAll(includeArchived: true).first) c.id: c,
    };
    for (final a in alerts) {
      final category = categories[a.categoryId];
      final name = category == null
          ? ''
          : category.isDefault && lang == 'es'
              ? (esDefaultNames[category.name] ?? category.name)
              : category.name;
      await service.show(
        id: a.id,
        title: _tr(lang, a.title),
        body: _tr(lang, a.body, {'name': name}),
        channelId: _budgetChannel,
        channelName: _tr(lang, 'Budget alerts'),
        sound: sound,
      );
    }
  } on Object {
    // Never break the app over a notification.
  }
});

Set<String> _decode(String? raw) {
  if (raw == null) return {};
  try {
    return (jsonDecode(raw) as List<Object?>).whereType<String>().toSet();
  } on Object {
    return {};
  }
}
