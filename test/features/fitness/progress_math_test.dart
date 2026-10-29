import 'package:flutter_test/flutter_test.dart';
import 'package:mykit/features/fitness/domain/default_plan.dart';
import 'package:mykit/features/fitness/domain/entities/fitness_entities.dart';
import 'package:mykit/features/fitness/domain/progress_math.dart';

WorkoutSession _session(DateTime at, List<LoggedSet> sets, {String id = 'x'}) =>
    WorkoutSession(
      id: '$id${at.millisecondsSinceEpoch}',
      startedAt: at,
      finishedAt: at.add(const Duration(minutes: 40)),
      exercises: [ExerciseLog(exerciseId: id, sets: sets)],
    );

void main() {
  test('BMI for 100 kg at 181 cm', () {
    final bmi = ProgressMath.bmi(100, 181);
    expect(bmi, closeTo(30.5, 0.05));
    expect(ProgressMath.bmiLabel(bmi), 'Obese (class I)');
    expect(ProgressMath.healthyWeight(181), closeTo(81.6, 0.1));
  });

  test('personal best: e1RM for weights, reps for bodyweight', () {
    final sessions = [
      _session(DateTime(2026, 10, 1), const [
        LoggedSet(reps: 10, weightKg: 12),
        LoggedSet(reps: 6, weightKg: 14),
      ]),
      _session(DateTime(2026, 10, 8), const [
        LoggedSet(reps: 13, weightKg: 12),
      ]),
    ];
    final pb = ProgressMath.best('x', sessions)!;
    // 12×13 (e1RM 17.2) beats 14×6 (16.8) and 12×10 (16.0).
    expect(pb.set.reps, 13);
    expect(pb.label, '12 kg × 13');

    final bw = ProgressMath.best('x', [
      _session(DateTime(2026, 10, 1), const [
        LoggedSet(reps: 8),
        LoggedSet(reps: 11),
      ]),
    ])!;
    expect(bw.label, '11 reps');
  });

  test('double progression: ready when every set hits the top', () {
    const item = PlanItem(exerciseId: 'x', sets: 3, repsMin: 8, repsMax: 12);
    expect(ProgressMath.readyToProgress(item, null), isFalse);
    expect(
      ProgressMath.readyToProgress(item, const [
        LoggedSet(reps: 12, weightKg: 10),
        LoggedSet(reps: 12, weightKg: 10),
        LoggedSet(reps: 11, weightKg: 10),
      ]),
      isFalse,
    );
    expect(
      ProgressMath.readyToProgress(item, const [
        LoggedSet(reps: 12, weightKg: 10),
        LoggedSet(reps: 12, weightKg: 10),
        LoggedSet(reps: 13, weightKg: 10),
      ]),
      isTrue,
    );
    const plank = PlanItem(exerciseId: 'p', sets: 2, seconds: 30);
    expect(
      ProgressMath.readyToProgress(plank, const [
        LoggedSet(seconds: 31),
        LoggedSet(seconds: 30),
      ]),
      isTrue,
    );
  });

  test('week streak counts consecutive weeks with a workout', () {
    final now = DateTime(2026, 10, 29); // Thursday
    final days = [
      DateTime(2026, 10, 27), // this week
      DateTime(2026, 10, 20), // last week
      DateTime(2026, 10, 14), // two weeks ago
      DateTime(2026, 9, 20), // gap before this
    ];
    expect(ProgressMath.weekStreak(days, now), 3);
    // Nothing yet this week still keeps last week's streak.
    expect(ProgressMath.weekStreak(days.skip(1), now), 2);
    expect(ProgressMath.weekStreak(const [], now), 0);
  });

  test('plan, sessions and body entries survive JSON', () {
    final plan = defaultPlan();
    expect(plan, hasLength(4));
    expect({for (final r in plan) ...r.weekdays}, hasLength(4));
    final back = Routine.fromJson(plan.first.toJson());
    expect(back.items.length, plan.first.items.length);
    expect(back.items.last.seconds, 30);

    final s = _session(DateTime(2026, 10, 1), const [
      LoggedSet(reps: 10, weightKg: 12.5),
    ]);
    final s2 = WorkoutSession.fromJson(s.toJson());
    expect(s2.volume, 125);
    expect(s2.duration, const Duration(minutes: 40));

    final b = BodyEntry.fromJson(
      BodyEntry(
        date: DateTime(2026, 10, 1),
        weightKg: 99.4,
        waistCm: 104,
      ).toJson(),
    );
    expect(b.weightKg, 99.4);
    expect(b.measurement('waist'), 104);
    expect(b.chestCm, isNull);
  });
}
