import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../../core/tools/tool_switch.dart';

import '../../../core/i18n/i18n.dart';
import '../../fitness/domain/food.dart';
import 'app_signals.dart';

/// Something not done yet today.
typedef Nudge = ({String id, String text});

/// Gentle reminders for what's still open today — a meal not logged, the
/// lesson not read, quests not answered, tasks due. Each kind at most once a
/// day, never at night.
abstract final class Nudges {
  static const enabledKey = 'habits.nudges.on';
  static const _sentKey = 'habits.nudges.sent';
  static const task = 'habits.nudges';
  static const _uniqueName = 'mykit.habits.nudges';
  static const _notificationId = 7700;

  /// After these times (minutes after midnight) a thing counts as missed.
  static const _breakfastBy = 11 * 60;
  static const _lunchBy = 16 * 60;
  static const _dinnerBy = 21 * 60 + 30;
  static const _lessonBy = 20 * 60;
  static const _questsBy = 21 * 60;
  static const _tasksBy = 18 * 60;
  static const _quietFrom = 23 * 60;
  static const _quietUntil = 8 * 60;

  static bool enabled(SharedPreferences prefs) =>
      prefs.getBool(enabledKey) ?? true;

  /// What's still open at [now]. With [all] (the panel in the app), the
  /// lesson, workout, quests and tasks show all day; meals only once their
  /// time has passed.
  static List<Nudge> open(AppSignals s, DateTime now, {bool all = false}) {
    final m = now.hour * 60 + now.minute;
    bool past(int by) => all || m >= by;
    return [
      if (s.foodOn && m >= _breakfastBy && !s.meals.contains(Meal.breakfast))
        (id: 'breakfast', text: tr('Breakfast not logged')),
      if (s.foodOn && m >= _lunchBy && !s.meals.contains(Meal.lunch))
        (id: 'lunch', text: tr('Lunch not logged')),
      if (s.foodOn && m >= _dinnerBy && !s.meals.contains(Meal.dinner))
        (id: 'dinner', text: tr('Dinner not logged')),
      if (s.lessonOn && past(_lessonBy) && !s.lessonRead)
        (id: 'lesson', text: tr('Today\'s lesson not read')),
      if (s.workoutPlanned != null && !s.workoutDone && past(_questsBy))
        (
          id: 'workout',
          text: tr('Workout not done: {name}', {'name': s.workoutPlanned}),
        ),
      if (past(_questsBy) && s.questsAnswered < s.questsDue)
        (
          id: 'quests',
          text: tr('{n} quests not answered', {
            'n': s.questsDue - s.questsAnswered,
          }),
        ),
      if (past(_tasksBy) && s.tasksDue + s.tasksOverdue > 0)
        (
          id: 'tasks',
          text: tr('{n} tasks due', {'n': s.tasksDue + s.tasksOverdue}),
        ),
    ];
  }

  static bool quiet(DateTime now) {
    final m = now.hour * 60 + now.minute;
    return m >= _quietFrom || m < _quietUntil;
  }

  /// Checks about once an hour (WorkManager), or stops.
  static Future<void> sync({required bool enabled}) async {
    try {
      if (!enabled) {
        await Workmanager().cancelByUniqueName(_uniqueName);
        return;
      }
      await Workmanager().registerPeriodicTask(
        _uniqueName,
        task,
        frequency: const Duration(hours: 1),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } catch (_) {}
  }

  /// The background check: notifies about things that became overdue since
  /// the last check, once per kind per day.
  static Future<bool> run() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (!enabled(prefs) || !ToolSwitch.isOn(prefs, ToolIds.habits)) return true;
    final now = DateTime.now();
    if (quiet(now)) return true;
    I18n.applySaved(prefs);
    final signals = AppSignals.read(prefs, now: now);

    final sent = _sent(prefs, signals.day);
    final fresh = open(signals, now).where((n) => !sent.contains(n.id));
    if (fresh.isEmpty) return true;
    final items = fresh.toList();

    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await plugin.show(
      id: _notificationId,
      title: tr('[SYSTEM] Still to do today'),
      body: items.map((n) => n.text).join(' · '),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'habit_nudges',
          'Still to do',
          channelDescription: 'Reminders for things not done yet today',
          importance: Importance.defaultImportance,
        ),
      ),
    );
    await prefs.setString(
      _sentKey,
      jsonEncode({
        'day': signals.day,
        'ids': [...sent, ...items.map((n) => n.id)],
      }),
    );
    return true;
  }

  static Set<String> _sent(SharedPreferences prefs, String day) {
    try {
      final j = jsonDecode(prefs.getString(_sentKey) ?? '{}') as Map;
      if (j['day'] != day) return {};
      return {...(j['ids'] as List).cast<String>()};
    } catch (_) {
      return {};
    }
  }
}
