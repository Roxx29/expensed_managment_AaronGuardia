import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// Local notifications. Override `notificationServiceProvider` with a fake in
/// tests. Implementations never throw: platform errors are swallowed.
abstract interface class NotificationService {
  /// Asks the OS for permission; false if denied or unavailable.
  Future<bool> requestPermission();

  /// Shows a notification now.
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String channelId,
    required String channelName,
  });

  /// Schedules a one-off notification at [when] (an absolute instant).
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    required String channelId,
    required String channelName,
  });

  /// Cancels pending notifications whose id is in [first]..[last].
  Future<void> cancelRange(int first, int last);
}

class LocalNotificationService implements NotificationService {
  late final FlutterLocalNotificationsPlugin _plugin;
  Future<bool>? _ready;

  /// Initializes once; false where the plugin is unavailable (tests, desktop).
  Future<bool> _init() => _ready ??= () async {
        try {
          _plugin = FlutterLocalNotificationsPlugin();
          await _plugin.initialize(
            const InitializationSettings(
              android: AndroidInitializationSettings('@mipmap/ic_launcher'),
              // Permission is asked when the user turns a notification on.
              iOS: DarwinInitializationSettings(
                requestAlertPermission: false,
                requestBadgePermission: false,
                requestSoundPermission: false,
              ),
            ),
          );
          return true;
        } on Object {
          return false;
        }
      }();

  NotificationDetails _details(String channelId, String channelName) => NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          // Hide the text on the lock screen.
          visibility: NotificationVisibility.private,
        ),
        iOS: const DarwinNotificationDetails(),
      );

  @override
  Future<bool> requestPermission() async {
    if (!await _init()) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) return await android.requestNotificationsPermission() ?? false;
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) return await ios.requestPermissions(alert: true, badge: true, sound: true) ?? false;
      return false;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String channelId,
    required String channelName,
  }) async {
    if (!await _init()) return;
    try {
      await _plugin.show(id, title, body, _details(channelId, channelName));
    } on Object {
      // Best effort.
    }
  }

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    required String channelId,
    required String channelName,
  }) async {
    if (!await _init()) return;
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        // UTC needs no time-zone database and keeps the absolute instant.
        tz.TZDateTime.from(when, tz.UTC),
        _details(channelId, channelName),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } on Object {
      // E.g. the instant passed while scheduling; skipped.
    }
  }

  @override
  Future<void> cancelRange(int first, int last) async {
    if (!await _init()) return;
    try {
      for (final p in await _plugin.pendingNotificationRequests()) {
        if (p.id >= first && p.id <= last) await _plugin.cancel(p.id);
      }
    } on Object {
      // Best effort.
    }
  }
}
