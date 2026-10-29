import 'entities/fitness_entities.dart';

/// Pure calculations for progress views (unit-tested).
abstract final class ProgressMath {
  static double bmi(double weightKg, double heightCm) {
    final m = heightCm / 100;
    return weightKg / (m * m);
  }

  static String bmiLabel(double bmi) => switch (bmi) {
    < 18.5 => 'Underweight',
    < 25 => 'Healthy',
    < 30 => 'Overweight',
    < 35 => 'Obese (class I)',
    < 40 => 'Obese (class II)',
    _ => 'Obese (class III)',
  };

  /// Weight for a BMI of 24.9 at this height (top of the healthy range).
  static double healthyWeight(double heightCm) {
    final m = heightCm / 100;
    return 24.9 * m * m;
  }

  /// Estimated one-rep max (Epley).
  static double e1rm(LoggedSet s) =>
      s.weightKg <= 0 || s.reps <= 0 ? 0 : s.weightKg * (1 + s.reps / 30);

  /// Best performance of an exercise across sessions: heaviest e1RM for
  /// weighted sets, most reps for bodyweight, longest hold for timed.
  static PersonalBest? best(
    String exerciseId,
    Iterable<WorkoutSession> sessions,
  ) {
    PersonalBest? pb;
    for (final session in sessions) {
      for (final log in session.exercises) {
        if (log.exerciseId != exerciseId) continue;
        for (final s in log.sets) {
          final candidate = PersonalBest(
            set: s,
            date: session.startedAt,
            score: s.weightKg > 0
                ? e1rm(s)
                : s.seconds > 0
                ? s.seconds.toDouble()
                : s.reps.toDouble(),
          );
          if (pb == null || candidate.score > pb.score) pb = candidate;
        }
      }
    }
    return pb;
  }

  /// The sets logged for [exerciseId] in the most recent session that has it.
  static List<LoggedSet>? lastSets(
    String exerciseId,
    List<WorkoutSession> newestFirst,
  ) {
    for (final s in newestFirst) {
      for (final log in s.exercises) {
        if (log.exerciseId == exerciseId && log.sets.isNotEmpty) {
          return log.sets;
        }
      }
    }
    return null;
  }

  /// Double progression: every target set reached the top of the range last
  /// time, so it's time to add weight (or reps for bodyweight moves).
  static bool readyToProgress(PlanItem item, List<LoggedSet>? last) {
    if (last == null || last.length < item.sets) return false;
    if (item.timed) {
      return last.take(item.sets).every((s) => s.seconds >= item.seconds!);
    }
    return last.take(item.sets).every((s) => s.reps >= item.repsMax);
  }

  /// Consecutive weeks (Mon–Sun, current week included if it has one) with
  /// at least one workout.
  static int weekStreak(Iterable<DateTime> workoutDays, DateTime now) {
    DateTime weekStart(DateTime d) {
      final day = DateTime(d.year, d.month, d.day);
      return day.subtract(Duration(days: day.weekday - 1));
    }

    final weeks = {for (final d in workoutDays) weekStart(d)};
    var cursor = weekStart(now);
    if (!weeks.contains(cursor)) {
      cursor = cursor.subtract(const Duration(days: 7));
    }
    var streak = 0;
    while (weeks.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 7));
    }
    return streak;
  }
}

class PersonalBest {
  const PersonalBest({
    required this.set,
    required this.date,
    required this.score,
  });

  final LoggedSet set;
  final DateTime date;
  final double score;

  String get label => set.weightKg > 0
      ? '${_kg(set.weightKg)} kg × ${set.reps}'
      : set.seconds > 0
      ? '${set.seconds}s'
      : '${set.reps} reps';

  static String _kg(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}
