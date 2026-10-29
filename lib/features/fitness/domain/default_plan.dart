import 'entities/fitness_entities.dart';

/// Starter 4-day upper/lower plan for fat loss at home: dumbbells plus
/// bodyweight moves, beginner-friendly for a heavier lifter (incline push-ups,
/// floor press, low-impact conditioning), with a short finisher each day.
///
/// Progression ("double progression"): when every set reaches the top of the
/// rep range, add a little weight (or move to a harder variation).
List<Routine> defaultPlan() => const [
  Routine(
    id: 'upper-a',
    name: 'Upper A',
    weekdays: {DateTime.saturday},
    items: [
      PlanItem(
        exerciseId: 'Incline_Push-Up',
        note:
            'Hands on a table or sofa; lower the support as you get stronger.',
      ),
      PlanItem(exerciseId: 'Bent_Over_Two-Dumbbell_Row', repsMin: 10),
      PlanItem(exerciseId: 'Seated_Dumbbell_Press'),
      PlanItem(exerciseId: 'Dumbbell_Bicep_Curl', sets: 2, repsMin: 10),
      PlanItem(
        exerciseId: 'Standing_Dumbbell_Triceps_Extension',
        sets: 2,
        repsMin: 10,
      ),
      PlanItem(exerciseId: 'Plank', seconds: 30, restSeconds: 45),
    ],
  ),
  Routine(
    id: 'lower-a',
    name: 'Lower A',
    weekdays: {DateTime.sunday},
    items: [
      PlanItem(
        exerciseId: 'Goblet_Squat',
        repsMin: 10,
        note: 'Hold one dumbbell at your chest.',
        restSeconds: 90,
      ),
      PlanItem(
        exerciseId: 'Stiff-Legged_Dumbbell_Deadlift',
        repsMin: 10,
        restSeconds: 90,
        note: 'Hips back, flat back, slight knee bend.',
      ),
      PlanItem(
        exerciseId: 'Dumbbell_Rear_Lunge',
        sets: 2,
        repsMin: 8,
        repsMax: 10,
        perSide: true,
      ),
      PlanItem(exerciseId: 'Butt_Lift_Bridge', repsMin: 12, repsMax: 15),
      PlanItem(
        exerciseId: 'Standing_Dumbbell_Calf_Raise',
        sets: 2,
        repsMin: 12,
        repsMax: 15,
        restSeconds: 45,
      ),
      PlanItem(
        exerciseId: 'Dead_Bug',
        repsMin: 8,
        repsMax: 10,
        perSide: true,
        restSeconds: 45,
      ),
    ],
  ),
  Routine(
    id: 'upper-b',
    name: 'Upper B',
    weekdays: {DateTime.tuesday},
    items: [
      PlanItem(
        exerciseId: 'Dumbbell_Floor_Press',
        note: 'Lie on the floor; elbows touch down each rep.',
      ),
      PlanItem(exerciseId: 'One-Arm_Dumbbell_Row', repsMin: 10, perSide: true),
      PlanItem(
        exerciseId: 'Side_Lateral_Raise',
        repsMin: 12,
        repsMax: 15,
        restSeconds: 60,
      ),
      PlanItem(exerciseId: 'Hammer_Curls', sets: 2, repsMin: 10),
      PlanItem(
        exerciseId: 'Bench_Dips',
        sets: 2,
        note: 'On a sturdy chair; keep the feet close to make it easier.',
      ),
      PlanItem(
        exerciseId: 'Mountain_Climbers',
        seconds: 30,
        restSeconds: 45,
        note: 'Finisher: steady pace, hands on a bench if needed.',
      ),
    ],
  ),
  Routine(
    id: 'lower-b',
    name: 'Lower B',
    weekdays: {DateTime.wednesday},
    items: [
      PlanItem(exerciseId: 'Dumbbell_Squat', repsMin: 10, restSeconds: 90),
      PlanItem(
        exerciseId: 'Split_Squat_with_Dumbbells',
        repsMin: 8,
        repsMax: 10,
        perSide: true,
        restSeconds: 75,
      ),
      PlanItem(
        exerciseId: 'Dumbbell_Step_Ups',
        sets: 2,
        repsMin: 10,
        repsMax: 10,
        perSide: true,
        note: 'Use a low, stable step.',
      ),
      PlanItem(
        exerciseId: 'Single_Leg_Glute_Bridge',
        sets: 2,
        repsMin: 10,
        repsMax: 12,
        perSide: true,
      ),
      PlanItem(exerciseId: 'Superman', repsMin: 12, repsMax: 15),
      PlanItem(
        exerciseId: 'Air_Bike',
        repsMin: 20,
        repsMax: 20,
        restSeconds: 45,
        note: 'Finisher: 20 total, controlled.',
      ),
    ],
  ),
];
