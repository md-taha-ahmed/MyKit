import 'dart:math';

import '../../../core/i18n/i18n.dart';
import 'entities/fitness_entities.dart';

/// One place in a workout: what it trains and the exercises that can fill it
/// (all doable at home with dumbbells or bodyweight — no pull-up bar).
class PlanSlot {
  const PlanSlot(
    this.options, {
    this.sets = 3,
    this.repsMin = 8,
    this.repsMax = 12,
    this.seconds,
    this.restSeconds = 75,
  });

  /// Interchangeable exercises (free-exercise-db ids); the first is the default.
  final List<String> options;
  final int sets;
  final int repsMin;
  final int repsMax;

  /// Timed slot (plank…).
  final int? seconds;
  final int restSeconds;

  PlanItem item(String exerciseId) => PlanItem(
    exerciseId: exerciseId,
    sets: sets,
    repsMin: repsMin,
    repsMax: repsMax,
    seconds: seconds ?? timedExercises[exerciseId],
    restSeconds: restSeconds,
    perSide: perSideExercises.contains(exerciseId),
  );
}

class PlanDay {
  const PlanDay(this.id, this.name, this.weekday, this.slots);

  final String id;
  final String name;
  final int weekday;
  final List<PlanSlot> slots;
}

/// Done one arm / leg at a time: reps are per side.
const perSideExercises = {
  'One-Arm_Dumbbell_Row',
  'Dumbbell_Lunges',
  'Dumbbell_Rear_Lunge',
  'Split_Squat_with_Dumbbells',
  'Dumbbell_Step_Ups',
  'Single_Leg_Glute_Bridge',
  'Glute_Kickback',
  'Dumbbell_Seated_One-Leg_Calf_Raise',
  'One-Arm_Side_Laterals',
  'External_Rotation',
  'Concentration_Curls',
  'Standing_One-Arm_Dumbbell_Triceps_Extension',
  'Dead_Bug',
};

/// Held for time rather than counted.
const timedExercises = {
  'Plank': 40,
  'Side_Bridge': 30,
  'Mountain_Climbers': 30,
  'Isometric_Chest_Squeezes': 30,
};

/// The 5-day split: chest, back, legs, shoulders, arms (Saturday–Wednesday),
/// each finishing with core work. Double progression: when every set reaches
/// the top of the rep range, add a little weight or a harder variation.
const fiveDayPlan = [
  PlanDay('chest', 'Chest day', DateTime.saturday, [
    PlanSlot(
      [
        'Dumbbell_Floor_Press',
        'Pushups',
        'Dumbbell_Bench_Press',
        'Push-Up_Wide',
      ],
      sets: 4,
      restSeconds: 90,
    ),
    PlanSlot([
      'Push-Ups_With_Feet_Elevated',
      'Incline_Dumbbell_Press',
      'Decline_Push-Up',
      'Hammer_Grip_Incline_DB_Bench_Press',
    ]),
    PlanSlot(
      ['Dumbbell_Flyes', 'Incline_Dumbbell_Flyes', 'Isometric_Chest_Squeezes'],
      repsMin: 10,
      repsMax: 15,
      restSeconds: 60,
    ),
    PlanSlot(
      [
        'Incline_Push-Up',
        'Pushups_Close_and_Wide_Hand_Positions',
        'Push_Up_to_Side_Plank',
      ],
      sets: 2,
      repsMin: 10,
      repsMax: 15,
      restSeconds: 60,
    ),
    PlanSlot(['Plank', 'Crunches', 'Reverse_Crunch'], restSeconds: 45),
  ]),
  PlanDay('back', 'Back day', DateTime.sunday, [
    PlanSlot(
      [
        'Bent_Over_Two-Dumbbell_Row',
        'Bent_Over_Two-Dumbbell_Row_With_Palms_In',
      ],
      sets: 4,
      restSeconds: 90,
    ),
    PlanSlot(['One-Arm_Dumbbell_Row', 'Dumbbell_Incline_Row'], repsMin: 10),
    PlanSlot(
      [
        'Reverse_Flyes',
        'Bent_Over_Dumbbell_Rear_Delt_Raise_With_Head_On_Bench',
      ],
      repsMin: 12,
      repsMax: 15,
      restSeconds: 60,
    ),
    PlanSlot(
      ['Dumbbell_Shrug', 'Standing_Dumbbell_Upright_Row'],
      repsMin: 12,
      repsMax: 15,
      restSeconds: 60,
    ),
    PlanSlot(
      ['Superman', 'Hyperextensions_With_No_Hyperextension_Bench'],
      sets: 2,
      repsMin: 12,
      repsMax: 15,
      restSeconds: 45,
    ),
    PlanSlot(
      ['Dead_Bug', 'Side_Bridge', 'Russian_Twist'],
      sets: 2,
      repsMin: 8,
      repsMax: 12,
      restSeconds: 45,
    ),
  ]),
  PlanDay('legs', 'Leg day', DateTime.monday, [
    PlanSlot(
      ['Goblet_Squat', 'Dumbbell_Squat', 'Plie_Dumbbell_Squat'],
      sets: 4,
      restSeconds: 90,
    ),
    PlanSlot(
      ['Stiff-Legged_Dumbbell_Deadlift', 'Vertical_Swing'],
      repsMin: 10,
      restSeconds: 90,
    ),
    PlanSlot([
      'Dumbbell_Lunges',
      'Dumbbell_Rear_Lunge',
      'Split_Squat_with_Dumbbells',
      'Dumbbell_Step_Ups',
    ], repsMax: 10),
    PlanSlot(
      ['Butt_Lift_Bridge', 'Single_Leg_Glute_Bridge', 'Glute_Kickback'],
      repsMin: 12,
      repsMax: 15,
      restSeconds: 60,
    ),
    PlanSlot(
      [
        'Standing_Dumbbell_Calf_Raise',
        'Dumbbell_Seated_One-Leg_Calf_Raise',
        'Calf_Raise_On_A_Dumbbell',
      ],
      repsMin: 12,
      repsMax: 20,
      restSeconds: 45,
    ),
    PlanSlot(
      ['Mountain_Climbers', 'Freehand_Jump_Squat', 'Star_Jump'],
      sets: 2,
      repsMin: 10,
      repsMax: 15,
      restSeconds: 45,
    ),
  ]),
  PlanDay('shoulders', 'Shoulder day', DateTime.tuesday, [
    PlanSlot(
      [
        'Seated_Dumbbell_Press',
        'Standing_Dumbbell_Press',
        'Arnold_Dumbbell_Press',
        'Standing_Alternating_Dumbbell_Press',
      ],
      sets: 4,
      restSeconds: 90,
    ),
    PlanSlot(
      [
        'Side_Lateral_Raise',
        'Seated_Side_Lateral_Raise',
        'One-Arm_Side_Laterals',
      ],
      repsMin: 12,
      repsMax: 15,
      restSeconds: 60,
    ),
    PlanSlot(
      ['Front_Dumbbell_Raise', 'Front_Two-Dumbbell_Raise', 'Dumbbell_Scaption'],
      repsMin: 10,
      restSeconds: 60,
    ),
    PlanSlot(
      ['Reverse_Flyes', 'Seated_Bent-Over_Rear_Delt_Raise'],
      repsMin: 12,
      repsMax: 15,
      restSeconds: 60,
    ),
    PlanSlot(
      ['External_Rotation', 'Standing_Dumbbell_Upright_Row', 'Dumbbell_Shrug'],
      sets: 2,
      repsMin: 12,
      repsMax: 15,
      restSeconds: 45,
    ),
    PlanSlot(['Side_Bridge', 'Plank', 'Air_Bike'], sets: 2, restSeconds: 45),
  ]),
  PlanDay('arms', 'Arm day', DateTime.wednesday, [
    PlanSlot([
      'Dumbbell_Bicep_Curl',
      'Dumbbell_Alternate_Bicep_Curl',
      'Seated_Dumbbell_Curl',
    ]),
    PlanSlot([
      'Bench_Dips',
      'Close-Grip_Dumbbell_Press',
      'Lying_Dumbbell_Tricep_Extension',
    ]),
    PlanSlot(
      ['Hammer_Curls', 'Alternate_Hammer_Curl', 'Cross_Body_Hammer_Curl'],
      repsMin: 10,
      restSeconds: 60,
    ),
    PlanSlot(
      [
        'Standing_Dumbbell_Triceps_Extension',
        'Seated_Triceps_Press',
        'Standing_One-Arm_Dumbbell_Triceps_Extension',
      ],
      repsMin: 10,
      restSeconds: 60,
    ),
    PlanSlot(
      ['Concentration_Curls', 'Standing_Concentration_Curl', 'Zottman_Curl'],
      sets: 2,
      repsMin: 10,
      repsMax: 15,
      restSeconds: 60,
    ),
    PlanSlot(
      [
        'Tricep_Dumbbell_Kickback',
        'Incline_Push-Up_Close-Grip',
        'Standing_Bent-Over_Two-Arm_Dumbbell_Triceps_Extension',
      ],
      sets: 2,
      repsMin: 10,
      repsMax: 15,
      restSeconds: 60,
    ),
    PlanSlot(
      [
        'Seated_Dumbbell_Palms-Up_Wrist_Curl',
        'Seated_Dumbbell_Palms-Down_Wrist_Curl',
      ],
      sets: 2,
      repsMin: 12,
      repsMax: 20,
      restSeconds: 45,
    ),
  ]),
];

/// The starter plan with each slot's first exercise.
List<Routine> defaultPlan() => [
  for (final day in fiveDayPlan)
    Routine(
      id: day.id,
      // Saved as text, so named in the app's language when created.
      name: tr(day.name),
      weekdays: {day.weekday},
      items: [for (final slot in day.slots) slot.item(slot.options.first)],
    ),
];

/// The slot an exercise fills in [routineId] (a plan day), if any.
PlanSlot? slotFor(String routineId, String exerciseId) {
  for (final day in fiveDayPlan) {
    if (day.id != routineId) continue;
    for (final slot in day.slots) {
      if (slot.options.contains(exerciseId)) return slot;
    }
  }
  return null;
}

/// Exercises that can replace [exerciseId] in [routineId]: the other
/// options of its slot (empty when it isn't part of the plan).
List<String> alternativesFor(String routineId, String exerciseId) => [
  for (final id in slotFor(routineId, exerciseId)?.options ?? const <String>[])
    if (id != exerciseId) id,
];

/// Every plan exercise swapped for another of its slot (when the slot has
/// one), keeping each item's sets, reps and rest. Routines and exercises the
/// user added themselves are left alone.
List<Routine> shufflePlan(List<Routine> routines, [Random? random]) {
  final rng = random ?? Random();
  return [
    for (final r in routines)
      r.copyWith(
        items: [
          for (final item in r.items)
            switch (alternativesFor(r.id, item.exerciseId)) {
              [] => item,
              final others => swapExercise(
                item,
                others[rng.nextInt(others.length)],
              ),
            },
        ],
      ),
  ];
}

/// [item] with another exercise, keeping its sets, reps and rest; whether it
/// is per side or timed follows the new exercise.
PlanItem swapExercise(PlanItem item, String exerciseId) {
  final seconds = timedExercises[exerciseId];
  final wasTimed = item.timed && timedExercises.containsKey(item.exerciseId);
  return PlanItem(
    exerciseId: exerciseId,
    sets: item.sets,
    repsMin: item.repsMin,
    repsMax: item.repsMax,
    seconds: seconds ?? (wasTimed ? null : item.seconds),
    restSeconds: item.restSeconds,
    perSide: perSideExercises.contains(exerciseId),
  );
}
