import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../fitness/data/fitness_store.dart';
import '../../fitness/domain/food.dart';
import '../../knowledge/data/knowledge_store.dart';
import '../domain/habit_models.dart';
import 'habit_store.dart';

/// Today across MyKit, read straight from storage (so it also works in the
/// background reminder check): the lesson, meals, the workout, quests and
/// tasks.
class AppSignals {
  const AppSignals({
    required this.day,
    required this.lessonRead,
    required this.meals,
    required this.kcal,
    required this.workoutPlanned,
    required this.workoutDone,
    required this.questsDue,
    required this.questsAnswered,
    required this.tasksDue,
    required this.tasksOverdue,
  });

  final String day;
  final bool lessonRead;

  /// Meals with something logged today.
  final Set<Meal> meals;
  final int kcal;

  /// Name of today's planned workout, if any.
  final String? workoutPlanned;
  final bool workoutDone;
  final int questsDue;
  final int questsAnswered;
  final int tasksDue;
  final int tasksOverdue;

  static AppSignals read(SharedPreferences prefs, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final day = habitDay(today);

    final lessonRead = KnowledgeStore(prefs).history.any((l) => l.day == day);

    final meals = <Meal>{};
    var kcal = 0;
    try {
      final raw = prefs.getString('fitness.food.v1');
      for (final j in raw == null ? const [] : jsonDecode(raw) as List) {
        final e = FoodEntry.fromJson(j as Map<String, dynamic>);
        if (e.day != day) continue;
        meals.add(e.meal);
        kcal += e.kcal;
      }
    } catch (_) {}

    final fitness = FitnessStore(prefs);
    final routine = (fitness.readRoutines() ?? const [])
        .where((r) => r.weekdays.contains(today.weekday))
        .firstOrNull;
    final workoutDone = fitness.readSessions().any(
      (s) => habitDay(s.startedAt) == day,
    );

    final habits = HabitStore(prefs);
    final due = habits.habits.where((h) => h.dueOn(today)).toList();
    final checks = {
      for (final c in habits.checkIns)
        if (c.day == day) c.habitId,
    };
    final tasks = habits.tasks.where((t) => !t.done);

    return AppSignals(
      day: day,
      lessonRead: lessonRead,
      meals: meals,
      kcal: kcal,
      workoutPlanned: routine?.name,
      workoutDone: workoutDone,
      questsDue: due.length,
      questsAnswered: due.where((h) => checks.contains(h.id)).length,
      tasksDue: tasks.where((t) => t.due == day).length,
      tasksOverdue: tasks.where((t) => t.overdue(today)).length,
    );
  }

  /// For the System: one line per part of the app.
  String describe({int? kcalTarget, int? socialMinutes, int? socialUsual}) {
    final b = StringBuffer()
      ..writeln('TODAY ACROSS THE APP ($day):')
      ..writeln(
        '  daily lesson (history/deen): ${lessonRead ? 'read' : 'not read yet'}',
      )
      ..writeln(
        '  food: $kcal kcal${kcalTarget == null ? '' : ' of $kcalTarget target'}; meals logged: ${meals.isEmpty ? 'none' : meals.map((m) => m.name).join(', ')}',
      )
      ..writeln(
        '  workout: ${workoutPlanned == null ? 'rest day' : '$workoutPlanned ${workoutDone ? 'done' : 'not done'}'}',
      )
      ..writeln('  quests answered: $questsAnswered of $questsDue')
      ..writeln('  tasks: $tasksDue due today, $tasksOverdue overdue');
    if (socialMinutes != null) {
      b.writeln(
        '  social media today: $socialMinutes min'
        '${socialUsual == null || socialUsual == 0 ? '' : ' (usual ~$socialUsual min/day)'}'
        ' — heavy scrolling often means a low mood for this user',
      );
    }
    return b.toString();
  }
}
