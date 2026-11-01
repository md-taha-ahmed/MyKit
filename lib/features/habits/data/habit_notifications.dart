import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/i18n/i18n.dart';
import '../domain/habit_models.dart';

/// A reminder for each habit at its time, on its days. The phone's current
/// time zone is used, so moving to another country keeps reminders at the
/// same local time.
class HabitNotifications {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _base = 7600;

  /// Room for 60 habits × 7 weekdays.
  static const _slots = 60 * 8;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'habit_quests',
      'Habit quests',
      channelDescription: 'Reminders for your daily habits',
      importance: Importance.defaultImportance,
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

  Future<bool> requestPermission() async {
    if (!await _init()) return false;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationsPermission() ?? true;
  }

  Future<void> schedule(List<Habit> habits) async {
    if (!await _init()) return;
    for (var i = 0; i < _slots; i++) {
      await _plugin.cancel(id: _base + i);
    }
    final now = tz.TZDateTime.now(tz.local);
    for (final (n, h) in habits.take(60).indexed) {
      final minutes = h.reminderMinutes;
      if (minutes == null) continue;
      for (final day in h.weekdays) {
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
          id: _base + n * 8 + day,
          scheduledDate: at,
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          title: tr('[Quest] {name}', {'name': h.name}),
          body: h.anchor.isEmpty
              ? h.tiny
              : tr('After {anchor}: {tiny}', {
                  'anchor': h.anchor,
                  'tiny': h.tiny,
                }),
        );
      }
    }
  }
}
