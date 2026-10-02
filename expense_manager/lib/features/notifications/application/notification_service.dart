import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// Notification sounds. Custom ones are WAVs in android/app/src/main/res/raw
/// (kept from resource shrinking by res/raw/keep.xml).
abstract final class NotificationSounds {
  static const system = 'default';
  static const silent = 'silent';
  static const all = [system, 'monchi_coin', 'monchi_bell', 'monchi_chime', silent];

  static String parse(String? value) => all.contains(value) ? value! : system;

  /// Android fixes a channel's sound when it is created, so each sound gets
  /// its own channel. The system sound keeps the original channel id.
  static String channelId(String base, String sound) => sound == system ? base : '${base}_$sound';
}

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
    String sound = NotificationSounds.system,
  });

  /// Schedules a one-off notification at [when] (an absolute instant).
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    required String channelId,
    required String channelName,
    String sound = NotificationSounds.system,
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

  // ponytail: custom sounds are Android-only; iOS plays the system sound
  // (add .caf files to the iOS bundle if the app ships on iPhone).
  NotificationDetails _details(String channelId, String channelName, String sound) => NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationSounds.channelId(channelId, sound),
          channelName,
          // Hide the text on the lock screen.
          visibility: NotificationVisibility.private,
          playSound: sound != NotificationSounds.silent,
          sound: sound == NotificationSounds.system || sound == NotificationSounds.silent
              ? null
              : RawResourceAndroidNotificationSound(sound),
        ),
        iOS: DarwinNotificationDetails(presentSound: sound != NotificationSounds.silent),
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
    String sound = NotificationSounds.system,
  }) async {
    if (!await _init()) return;
    try {
      await _plugin.show(id, title, body, _details(channelId, channelName, sound));
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
    String sound = NotificationSounds.system,
  }) async {
    if (!await _init()) return;
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        // UTC needs no time-zone database and keeps the absolute instant.
        tz.TZDateTime.from(when, tz.UTC),
        _details(channelId, channelName, sound),
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
