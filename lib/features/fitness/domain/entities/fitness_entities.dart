/// Models for the Fitness tool (home workouts: dumbbells + calisthenics).
library;

/// Muscle groups as named by the exercise database.
abstract final class Muscle {
  static const abdominals = 'abdominals';
  static const abductors = 'abductors';
  static const adductors = 'adductors';
  static const biceps = 'biceps';
  static const calves = 'calves';
  static const chest = 'chest';
  static const forearms = 'forearms';
  static const glutes = 'glutes';
  static const hamstrings = 'hamstrings';
  static const lats = 'lats';
  static const lowerBack = 'lower back';
  static const middleBack = 'middle back';
  static const neck = 'neck';
  static const quadriceps = 'quadriceps';
  static const shoulders = 'shoulders';
  static const traps = 'traps';
  static const triceps = 'triceps';

  static const all = [
    chest,
    shoulders,
    biceps,
    triceps,
    forearms,
    abdominals,
    lats,
    middleBack,
    lowerBack,
    traps,
    glutes,
    quadriceps,
    hamstrings,
    adductors,
    abductors,
    calves,
    neck,
  ];

  static String label(String m) => switch (m) {
    abdominals => 'Abs',
    lowerBack => 'Lower back',
    middleBack => 'Upper back',
    quadriceps => 'Quads',
    _ => m[0].toUpperCase() + m.substring(1),
  };
}

/// One exercise from the library (public-domain free-exercise-db) or
/// created by the user.
class Exercise {
  const Exercise({
    required this.id,
    required this.name,
    this.equipment,
    this.level = 'beginner',
    this.category = 'strength',
    this.primaryMuscles = const [],
    this.secondaryMuscles = const [],
    this.instructions = const [],
    this.images = const [],
    this.custom = false,
  });

  final String id;
  final String name;

  /// "body only", "dumbbell", "kettlebells", … (null = none listed).
  final String? equipment;
  final String level;
  final String category;
  final List<String> primaryMuscles;
  final List<String> secondaryMuscles;
  final List<String> instructions;

  /// Paths relative to the database's image folder (start / end position).
  final List<String> images;

  /// Created by the user (not in the database).
  final bool custom;

  /// Doable at home with dumbbells or nothing.
  bool get isHome =>
      equipment == null ||
      equipment == 'body only' ||
      equipment == 'dumbbell' ||
      equipment == 'kettlebells';

  bool get usesWeight => equipment == 'dumbbell' || equipment == 'kettlebells';

  String get equipmentLabel => switch (equipment) {
    null || 'body only' => 'Bodyweight',
    'kettlebells' => 'Dumbbell / kettlebell',
    final e => e[0].toUpperCase() + e.substring(1),
  };

  factory Exercise.fromJson(Map<String, dynamic> j) => Exercise(
    id: j['id'] as String,
    name: j['name'] as String,
    equipment: j['equipment'] as String?,
    level: j['level'] as String? ?? 'beginner',
    category: j['category'] as String? ?? 'strength',
    primaryMuscles: [...(j['primaryMuscles'] as List? ?? const []).cast()],
    secondaryMuscles: [...(j['secondaryMuscles'] as List? ?? const []).cast()],
    instructions: [...(j['instructions'] as List? ?? const []).cast()],
    images: [...(j['images'] as List? ?? const []).cast()],
    custom: j['custom'] as bool? ?? false,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'equipment': equipment,
    'level': level,
    'category': category,
    'primaryMuscles': primaryMuscles,
    'secondaryMuscles': secondaryMuscles,
    'instructions': instructions,
    'images': images,
    'custom': custom,
  };
}

/// One exercise in a routine, with its target.
class PlanItem {
  const PlanItem({
    required this.exerciseId,
    this.sets = 3,
    this.repsMin = 8,
    this.repsMax = 12,
    this.seconds,
    this.restSeconds = 75,
    this.perSide = false,
    this.note,
  });

  final String exerciseId;
  final int sets;
  final int repsMin;
  final int repsMax;

  /// Timed exercise (plank…): hold / work this long instead of reps.
  final int? seconds;
  final int restSeconds;

  /// Reps are per leg / arm.
  final bool perSide;
  final String? note;

  bool get timed => seconds != null;

  String get target {
    final reps = timed
        ? '${seconds}s'
        : repsMin == repsMax
        ? '$repsMin'
        : '$repsMin–$repsMax';
    return '$sets × $reps${perSide ? ' / side' : ''}';
  }

  PlanItem copyWith({
    int? sets,
    int? repsMin,
    int? repsMax,
    int? seconds,
    bool clearSeconds = false,
    int? restSeconds,
    bool? perSide,
  }) => PlanItem(
    exerciseId: exerciseId,
    sets: sets ?? this.sets,
    repsMin: repsMin ?? this.repsMin,
    repsMax: repsMax ?? this.repsMax,
    seconds: clearSeconds ? null : seconds ?? this.seconds,
    restSeconds: restSeconds ?? this.restSeconds,
    perSide: perSide ?? this.perSide,
    note: note,
  );

  Map<String, Object?> toJson() => {
    'exerciseId': exerciseId,
    'sets': sets,
    'repsMin': repsMin,
    'repsMax': repsMax,
    'seconds': seconds,
    'restSeconds': restSeconds,
    'perSide': perSide,
    'note': note,
  };

  factory PlanItem.fromJson(Map<String, dynamic> j) => PlanItem(
    exerciseId: j['exerciseId'] as String,
    sets: j['sets'] as int? ?? 3,
    repsMin: j['repsMin'] as int? ?? 8,
    repsMax: j['repsMax'] as int? ?? 12,
    seconds: j['seconds'] as int?,
    restSeconds: j['restSeconds'] as int? ?? 75,
    perSide: j['perSide'] as bool? ?? false,
    note: j['note'] as String?,
  );
}

/// A workout day, e.g. "Upper A", scheduled on some weekdays.
class Routine {
  const Routine({
    required this.id,
    required this.name,
    this.weekdays = const {},
    this.items = const [],
  });

  final String id;
  final String name;

  /// DateTime.monday … DateTime.sunday.
  final Set<int> weekdays;
  final List<PlanItem> items;

  Routine copyWith({String? name, Set<int>? weekdays, List<PlanItem>? items}) =>
      Routine(
        id: id,
        name: name ?? this.name,
        weekdays: weekdays ?? this.weekdays,
        items: items ?? this.items,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'weekdays': weekdays.toList()..sort(),
    'items': [for (final i in items) i.toJson()],
  };

  factory Routine.fromJson(Map<String, dynamic> j) => Routine(
    id: j['id'] as String,
    name: j['name'] as String,
    weekdays: {...(j['weekdays'] as List? ?? const []).cast<int>()},
    items: [
      for (final i in (j['items'] as List? ?? const []))
        PlanItem.fromJson(i as Map<String, dynamic>),
    ],
  );
}

/// One performed set.
class LoggedSet {
  const LoggedSet({this.reps = 0, this.weightKg = 0, this.seconds = 0});

  final int reps;
  final double weightKg;
  final int seconds;

  /// Lifted volume (kg × reps); bodyweight sets count 0.
  double get volume => reps * weightKg;

  Map<String, Object?> toJson() => {
    'reps': reps,
    'kg': weightKg,
    if (seconds > 0) 's': seconds,
  };

  factory LoggedSet.fromJson(Map<String, dynamic> j) => LoggedSet(
    reps: j['reps'] as int? ?? 0,
    weightKg: (j['kg'] as num?)?.toDouble() ?? 0,
    seconds: j['s'] as int? ?? 0,
  );
}

class ExerciseLog {
  const ExerciseLog({required this.exerciseId, this.sets = const []});

  final String exerciseId;
  final List<LoggedSet> sets;

  Map<String, Object?> toJson() => {
    'exerciseId': exerciseId,
    'sets': [for (final s in sets) s.toJson()],
  };

  factory ExerciseLog.fromJson(Map<String, dynamic> j) => ExerciseLog(
    exerciseId: j['exerciseId'] as String,
    sets: [
      for (final s in (j['sets'] as List? ?? const []))
        LoggedSet.fromJson(s as Map<String, dynamic>),
    ],
  );
}

/// A finished workout.
class WorkoutSession {
  const WorkoutSession({
    required this.id,
    required this.startedAt,
    required this.finishedAt,
    this.routineId,
    this.routineName,
    this.exercises = const [],
  });

  final String id;
  final DateTime startedAt;
  final DateTime finishedAt;
  final String? routineId;
  final String? routineName;
  final List<ExerciseLog> exercises;

  Duration get duration => finishedAt.difference(startedAt);

  int get setCount => exercises.fold(0, (n, e) => n + e.sets.length);

  double get volume => exercises.fold(
    0.0,
    (v, e) => v + e.sets.fold(0.0, (s, x) => s + x.volume),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'start': startedAt.toIso8601String(),
    'end': finishedAt.toIso8601String(),
    'routineId': routineId,
    'routineName': routineName,
    'exercises': [for (final e in exercises) e.toJson()],
  };

  factory WorkoutSession.fromJson(Map<String, dynamic> j) => WorkoutSession(
    id: j['id'] as String,
    startedAt: DateTime.parse(j['start'] as String),
    finishedAt: DateTime.parse(j['end'] as String),
    routineId: j['routineId'] as String?,
    routineName: j['routineName'] as String?,
    exercises: [
      for (final e in (j['exercises'] as List? ?? const []))
        ExerciseLog.fromJson(e as Map<String, dynamic>),
    ],
  );
}

/// Body weight and optional measurements on a day.
class BodyEntry {
  const BodyEntry({
    required this.date,
    this.weightKg,
    this.waistCm,
    this.chestCm,
    this.armCm,
    this.hipsCm,
    this.thighCm,
  });

  final DateTime date;
  final double? weightKg;
  final double? waistCm;
  final double? chestCm;
  final double? armCm;
  final double? hipsCm;
  final double? thighCm;

  static const measurements = ['waist', 'chest', 'arm', 'hips', 'thigh'];

  double? measurement(String key) => switch (key) {
    'waist' => waistCm,
    'chest' => chestCm,
    'arm' => armCm,
    'hips' => hipsCm,
    'thigh' => thighCm,
    _ => null,
  };

  Map<String, Object?> toJson() => {
    'date': date.toIso8601String(),
    'weight': ?weightKg,
    'waist': ?waistCm,
    'chest': ?chestCm,
    'arm': ?armCm,
    'hips': ?hipsCm,
    'thigh': ?thighCm,
  };

  factory BodyEntry.fromJson(Map<String, dynamic> j) {
    double? d(String k) => (j[k] as num?)?.toDouble();
    return BodyEntry(
      date: DateTime.parse(j['date'] as String),
      weightKg: d('weight'),
      waistCm: d('waist'),
      chestCm: d('chest'),
      armCm: d('arm'),
      hipsCm: d('hips'),
      thighCm: d('thigh'),
    );
  }
}

/// The user's details, goal and reminder settings.
class FitnessProfile {
  const FitnessProfile({
    this.heightCm = 181,
    this.startWeightKg = 100,
    this.goalWeightKg = 85,
    this.remindersOn = false,
    this.reminderMinutes = 18 * 60,
  });

  final double heightCm;
  final double startWeightKg;
  final double goalWeightKg;
  final bool remindersOn;

  /// Minutes after midnight for the training-day reminder.
  final int reminderMinutes;

  FitnessProfile copyWith({
    double? heightCm,
    double? startWeightKg,
    double? goalWeightKg,
    bool? remindersOn,
    int? reminderMinutes,
  }) => FitnessProfile(
    heightCm: heightCm ?? this.heightCm,
    startWeightKg: startWeightKg ?? this.startWeightKg,
    goalWeightKg: goalWeightKg ?? this.goalWeightKg,
    remindersOn: remindersOn ?? this.remindersOn,
    reminderMinutes: reminderMinutes ?? this.reminderMinutes,
  );

  Map<String, Object?> toJson() => {
    'height': heightCm,
    'start': startWeightKg,
    'goal': goalWeightKg,
    'reminders': remindersOn,
    'reminderAt': reminderMinutes,
  };

  factory FitnessProfile.fromJson(Map<String, dynamic> j) => FitnessProfile(
    heightCm: (j['height'] as num?)?.toDouble() ?? 181,
    startWeightKg: (j['start'] as num?)?.toDouble() ?? 100,
    goalWeightKg: (j['goal'] as num?)?.toDouble() ?? 85,
    remindersOn: j['reminders'] as bool? ?? false,
    reminderMinutes: j['reminderAt'] as int? ?? 18 * 60,
  );
}
