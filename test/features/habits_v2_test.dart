import 'package:flutter_test/flutter_test.dart';
import 'package:mykit/features/fitness/domain/food.dart';
import 'package:mykit/features/habits/data/app_signals.dart';
import 'package:mykit/features/habits/data/nudges.dart';
import 'package:mykit/features/habits/domain/habit_models.dart';
import 'package:mykit/features/habits/domain/patterns.dart';

DaySnapshot _d(int i, int social, {bool done = true, int kcal = 2000}) =>
    DaySnapshot(
      day: '2026-10-${(i + 1).toString().padLeft(2, '0')}',
      socialMinutes: social,
      workoutPlanned: true,
      workoutDone: done,
      kcal: kcal,
      kcalTarget: 2200,
      meals: 3,
    );

AppSignals _signals({
  Set<Meal> meals = const {},
  bool lesson = false,
  int questsDue = 2,
  int answered = 0,
}) => AppSignals(
  day: '2026-11-01',
  lessonRead: lesson,
  meals: meals,
  kcal: 0,
  workoutPlanned: null,
  workoutDone: false,
  questsDue: questsDue,
  questsAnswered: answered,
  tasksDue: 0,
  tasksOverdue: 0,
);

void main() {
  test('Hijri dates (tabular, ±1 day)', () {
    // 1 Ramadan 1447 ≈ 18–19 Feb 2026.
    final r = Hijri.of(DateTime(2026, 2, 19));
    expect(r.year, 1447);
    expect(r.month, 9);
    expect(r.day, inInclusiveRange(1, 2));
    expect(Hijri.of(DateTime(2026, 11, 1)).year, 1448);
  });

  test('heavy-scrolling days skip workouts and overeat: found', () {
    final days = [
      for (var i = 0; i < 6; i++) _d(i, 60), // normal: done, on target
      for (var i = 6; i < 10; i++) _d(i, 200, done: false, kcal: 2900),
    ];
    expect(DayPatterns.usualSocial(days), 60);
    final p = DayPatterns.find(days);
    final workout = p.firstWhere((x) => x.text == 'Workout done');
    expect(workout.onHeavy, 0);
    expect(workout.onNormal, 1);
    expect(p.any((x) => x.text == 'Ate over your target'), isTrue);
  });

  test('no patterns without enough days', () {
    expect(DayPatterns.find([_d(0, 60), _d(1, 300)]), isEmpty);
  });

  test('typical time: median of done check-ins', () {
    final now = DateTime(2026, 11, 1, 22);
    final checks = [
      for (var i = 1; i <= 6; i++)
        CheckIn(
          habitId: 'h',
          day: '2026-10-2$i',
          status: CheckStatus.full,
          at: DateTime(2026, 10, 25 + i ~/ 6, 17, 20 + i),
        ),
    ];
    expect(DayPatterns.typicalTime(checks, now: now), 17 * 60 + 24);
  });

  test('still to do: meals only after their time, the rest by evening', () {
    final morning = Nudges.open(_signals(), DateTime(2026, 11, 1, 9));
    expect(morning, isEmpty);
    final noon = Nudges.open(_signals(), DateTime(2026, 11, 1, 12));
    expect(noon.map((n) => n.id), ['breakfast']);
    final night = Nudges.open(
      _signals(meals: {Meal.breakfast}),
      DateTime(2026, 11, 1, 22),
    );
    expect(night.map((n) => n.id), ['lunch', 'dinner', 'lesson', 'quests']);
    // In the app the lesson and quests show all day.
    final panel = Nudges.open(_signals(), DateTime(2026, 11, 1, 9), all: true);
    expect(panel.map((n) => n.id), ['lesson', 'quests']);
    expect(Nudges.quiet(DateTime(2026, 11, 1, 23, 30)), isTrue);
    expect(Nudges.quiet(DateTime(2026, 11, 1, 9)), isFalse);
  });

  test('snapshots, tasks and the aid kit survive JSON', () {
    final d = DaySnapshot.fromJson(_d(0, 45).toJson());
    expect(d.socialMinutes, 45);
    expect(d.workoutDone, isTrue);
    final t = HabitTask.fromJson(
      HabitTask(
        id: 't',
        title: 'Call the bank',
        due: '2026-10-30',
        createdAt: DateTime(2026),
        fromSystem: true,
      ).toJson(),
    );
    expect(t.overdue(DateTime(2026, 11, 1)), isTrue);
    expect(t.fromSystem, isTrue);
    final e = AidEntry.fromJson(
      const AidEntry(
        id: 'a',
        feeling: 'Overstimulated',
        actions: [AidAction('x', 'Do a chore')],
      ).toJson(),
    );
    expect(e.actions.single.text, 'Do a chore');
  });
}
