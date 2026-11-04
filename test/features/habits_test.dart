import 'package:flutter_test/flutter_test.dart';
import 'package:mykit/features/habits/data/habit_coach.dart';
import 'package:mykit/features/habits/domain/habit_analysis.dart';
import 'package:mykit/features/habits/domain/habit_models.dart';

Habit _habit({DateTime? created}) => Habit(
  id: 'h',
  name: 'Workout',
  stat: HabitStat.strength,
  tiny: '5 push-ups',
  full: 'Full workout',
  anchor: 'Asr prayer',
  createdAt: created ?? DateTime(2026, 10, 1),
);

CheckIn _c(String day, CheckStatus s, [MissReason? r]) =>
    CheckIn(habitId: 'h', day: day, status: s, at: DateTime(2026), reason: r);

void main() {
  final now = DateTime(2026, 11, 5);

  test('XP: full, tiny, recovery after a miss, comeback after a hard day', () {
    final checks = [
      _c('2026-11-01', CheckStatus.full), // 10
      _c('2026-11-02', CheckStatus.missed, MissReason.fear), // 0
      _c('2026-11-03', CheckStatus.tiny), // 6 + 5 recovery
      _c('2026-11-04', CheckStatus.excused, MissReason.noPower), // 0
      _c('2026-11-05', CheckStatus.full), // 10 + 3 resilience
    ];
    expect(HabitAnalysis.totalXp(checks, const [], const {}), 34);
    expect(HabitAnalysis.level(34).level, 1);
    expect(HabitAnalysis.level(50).level, 2);
  });

  test('streak: hard days and excused days don\'t break it; a miss does', () {
    final h = _habit();
    final checks = {
      for (final c in [
        _c('2026-11-01', CheckStatus.missed),
        _c('2026-11-02', CheckStatus.full),
        _c('2026-11-03', CheckStatus.excused, MissReason.security),
        _c('2026-11-04', CheckStatus.tiny),
      ])
        c.day: c,
    };
    // 11-05 (today) unanswered doesn't count yet.
    expect(HabitAnalysis.streak(h, checks, const {}, now: now), 2);
    expect(HabitAnalysis.streak(h, checks, const {'2026-11-01'}, now: now), 2);
  });

  test('never miss twice: a miss yesterday makes today a recovery quest', () {
    final h = _habit();
    final missed = {'2026-11-04': _c('2026-11-04', CheckStatus.missed)};
    expect(HabitAnalysis.recoveryToday(h, missed, now: now), isTrue);
    final done = {'2026-11-04': _c('2026-11-04', CheckStatus.tiny)};
    expect(HabitAnalysis.recoveryToday(h, done, now: now), isFalse);
  });

  test('rank follows automaticity, S needs time and repeated high scores', () {
    final h = _habit(
      created: DateTime.now().subtract(const Duration(days: 70)),
    );
    AutomaticityCheck w(int days, int score) => AutomaticityCheck(
      'h',
      DateTime.now().subtract(Duration(days: days)),
      [score, score, score, score],
    );
    expect(HabitAnalysis.rank(const [], h), HabitRank.e);
    expect(HabitAnalysis.rank([w(1, 4)], h), HabitRank.c);
    expect(HabitAnalysis.rank([w(1, 6)], h), HabitRank.a);
    expect(HabitAnalysis.rank([w(8, 6), w(1, 7)], h), HabitRank.s);
  });

  test('outside reasons are excused', () {
    expect(MissReason.noPower.external, isTrue);
    expect(MissReason.security.external, isTrue);
    expect(MissReason.fear.external, isFalse);
  });

  test('the System\'s reply: visible text and its proposal', () {
    const text = '''
You weren't lazy: the pull-up felt like proof you're weak, so you avoided the whole workout.

```json
{"insight": "Avoids back day because pull-ups feel impossible",
 "understanding": {"root": "fear of failing at pull-ups", "evidence": "skipped back day 3 times, pull-ups skipped in 4 of 4", "helps": "easier progressions", "fails": "all-or-nothing plans", "confidence": 70},
 "life": "",
 "changes": [{"type": "swap_exercise", "routine": "back", "index": 0, "to": "One-Arm_Dumbbell_Row"},
             {"type": "tiny", "text": "Do the first exercise only"}],
 "next": "Tomorrow: one set of rows, then decide"}
```''';
    final r = HabitCoach.parse(text);
    expect(r.text, startsWith('You weren\'t lazy'));
    expect(r.text, isNot(contains('```')));
    final p = r.proposal!;
    expect(p.understanding.rootCause, 'fear of failing at pull-ups');
    expect(p.understanding.confidence, 70);
    expect(p.life, isNull);
    expect(p.changes.map((c) => c.type), ['swap_exercise', 'tiny']);
    expect(p.next, contains('rows'));
  });

  test('context packs the history, the understanding and the workout', () {
    final ctx = HabitCoach.context(
      habit: _habit(),
      checks: [_c('2026-11-04', CheckStatus.missed, MissReason.fear)],
      understanding: const HabitUnderstanding(rootCause: 'fear of pull-ups'),
      life: const LifeContext(summary: 'Lives in Yemen; power cuts at night'),
      notes: const [],
      hardDays: const {},
      now: now,
      workout: const WorkoutContext(
        routineId: 'back',
        routineName: 'Back day',
        exercises: [
          (
            index: 0,
            id: 'Pullups',
            name: 'Pullups',
            target: '3 × 8–12',
            skipped: 4,
            sessions: 4,
            alternatives: [(id: 'One-Arm_Dumbbell_Row', name: 'One-Arm Row')],
          ),
        ],
      ),
    );
    expect(ctx, contains('2026-11-04 ✗ (fear'));
    expect(ctx, contains('fear of pull-ups'));
    expect(ctx, contains('power cuts'));
    expect(ctx, contains('skipped in 4 of last 4'));
    expect(ctx, contains('[One-Arm_Dumbbell_Row]'));
  });
}
