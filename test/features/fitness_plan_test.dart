import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mykit/features/fitness/domain/default_plan.dart';

void main() {
  test('5 days: chest, back, legs, shoulders, arms; no pull-up bar', () {
    final plan = defaultPlan();
    expect(plan.map((r) => r.id), [
      'chest',
      'back',
      'legs',
      'shoulders',
      'arms',
    ]);
    expect(plan.map((r) => r.weekdays.single).toSet().length, 5);
    for (final day in fiveDayPlan) {
      for (final slot in day.slots) {
        for (final id in slot.options) {
          expect(id.toLowerCase(), isNot(matches(RegExp('pull|chin|hanging'))));
        }
      }
    }
  });

  test(
    'shuffle swaps every exercise within its slot and keeps the targets',
    () {
      final plan = defaultPlan();
      final shuffled = shufflePlan(plan, Random(1));
      for (final (r, routine) in plan.indexed) {
        for (final (i, item) in routine.items.indexed) {
          final after = shuffled[r].items[i];
          final slot = fiveDayPlan[r].slots[i];
          expect(slot.options, contains(after.exerciseId));
          if (slot.options.length > 1) {
            expect(after.exerciseId, isNot(item.exerciseId));
          }
          expect(after.sets, item.sets);
          expect(after.restSeconds, item.restSeconds);
          expect(after.perSide, perSideExercises.contains(after.exerciseId));
        }
      }
    },
  );

  test('exercises added by hand are left alone', () {
    final plan = defaultPlan();
    final custom = plan.first.copyWith(
      items: [
        ...plan.first.items,
        swapExercise(plan.first.items.first, 'Burpee'),
      ],
    );
    final shuffled = shufflePlan([custom], Random(2));
    expect(shuffled.first.items.last.exerciseId, 'Burpee');
  });
}
