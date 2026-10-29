import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Training-day reminders and the end-of-rest alert (works with the screen
/// off). Inexact alarms, so no special permission is needed.
class FitnessNotifications {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _reminderBase = 7100; // + weekday (1–7)
  static const _restId = 7200;

  static const _reminderDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'fitness_reminders',
      'Workout reminders',
      channelDescription: 'Reminds you on training days',
      importance: Importance.defaultImportance,
    ),
  );

  static const _restDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'fitness_rest',
      'Rest timer',
      channelDescription: 'Tells you when the rest between sets is over',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  Future<bool> _init() async {
    if (_ready) return true;
    try {
      tzdata.initializeTimeZones();
      final local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local.identifier));
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      _ready = true;
    } catch (_) {
      _ready = false;
    }
    return _ready;
  }

  /// Asks for notification permission (Android 13+). True if allowed.
  Future<bool> requestPermission() async {
    if (!await _init()) return false;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationsPermission() ?? true;
  }

  /// Weekly reminders on [weekdays] at [minutes] after midnight; replaces
  /// any previous ones. Empty [weekdays] just cancels.
  Future<void> scheduleReminders(
    Set<int> weekdays,
    int minutes, {
    String Function(int weekday)? bodyFor,
  }) async {
    if (!await _init()) return;
    for (var d = 1; d <= 7; d++) {
      await _plugin.cancel(id: _reminderBase + d);
    }
    final now = tz.TZDateTime.now(tz.local);
    for (final day in weekdays) {
      var at = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        minutes ~/ 60,
        minutes % 60,
      );
      while (at.weekday != day || !at.isAfter(now)) {
        at = at.add(const Duration(days: 1));
      }
      await _plugin.zonedSchedule(
        id: _reminderBase + day,
        scheduledDate: at,
        notificationDetails: _reminderDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        title: 'Workout day 💪',
        body: bodyFor?.call(day) ?? 'Time for today\'s workout.',
      );
    }
  }

  /// Alerts when the rest is over, even if the app is in the background.
  Future<void> scheduleRestEnd(Duration rest, String next) async {
    if (!await _init()) return;
    await _plugin.cancel(id: _restId);
    await _plugin.zonedSchedule(
      id: _restId,
      scheduledDate: tz.TZDateTime.now(tz.local).add(rest),
      notificationDetails: _restDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: 'Rest over',
      body: next,
    );
  }

  Future<void> cancelRest() async {
    if (!await _init()) return;
    await _plugin.cancel(id: _restId);
  }
}
