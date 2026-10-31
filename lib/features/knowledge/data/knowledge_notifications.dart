import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// "درس اليوم" every day at the chosen time (one weekly alarm per weekday,
/// so each can name its own topic). Inexact, so no special permission.
class KnowledgeNotifications {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _base = 7300; // + weekday (1–7)
  static const _articlesId = 7400;

  static const _articlesDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'knowledge_sources',
      'New articles',
      channelDescription: 'New articles on the sites you follow',
      importance: Importance.defaultImportance,
    ),
  );

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'knowledge_daily',
      'Daily lesson',
      channelDescription: 'Today\'s lesson in history and deen',
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

  /// Replaces the reminders; [topics] maps weekday → what that day teaches.
  /// Empty [topics] just cancels.
  Future<void> schedule(Map<int, String> topics, int minutes) async {
    if (!await _init()) return;
    for (var d = 1; d <= 7; d++) {
      await _plugin.cancel(id: _base + d);
    }
    final now = tz.TZDateTime.now(tz.local);
    for (final MapEntry(key: day, value: topic) in topics.entries) {
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
        id: _base + day,
        scheduledDate: at,
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        title: 'درس اليوم 📖',
        body: topic,
      );
    }
  }

  /// "3 مقالات جديدة من …" (replaces the previous one).
  Future<void> showNewArticles(
    Map<String, int> perSource,
    String firstTitle,
  ) async {
    if (perSource.isEmpty || !await _init()) return;
    final total = perSource.values.fold<int>(0, (a, b) => a + b);
    final names = perSource.keys.take(2).join('، ');
    await _plugin.show(
      id: _articlesId,
      title: '${_count(total)} من $names',
      body: firstTitle,
      notificationDetails: _articlesDetails,
    );
  }

  static String _count(int n) => switch (n) {
    1 => 'مقال جديد',
    2 => 'مقالان جديدان',
    <= 10 => '$n مقالات جديدة',
    _ => '$n مقالاً جديداً',
  };
}
