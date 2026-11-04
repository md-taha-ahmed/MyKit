/// Calorie counting: what was eaten, and a daily target worked out from
/// weight, height, age, sex, activity and goal (Mifflin–St Jeor).
library;

enum Meal {
  breakfast('Breakfast'),
  lunch('Lunch'),
  dinner('Dinner'),
  snack('Snack');

  const Meal(this.label);

  final String label;

  /// A sensible meal for the time of day.
  static Meal forTime(DateTime t) => switch (t.hour) {
    < 11 => Meal.breakfast,
    < 16 => Meal.lunch,
    < 21 => Meal.dinner,
    _ => Meal.snack,
  };
}

/// How an entry's calories were found.
enum FoodSource { manual, text, photo }

class FoodEntry {
  const FoodEntry({
    required this.id,
    required this.day,
    required this.at,
    required this.meal,
    required this.name,
    required this.kcal,
    this.source = FoodSource.manual,
  });

  final String id;

  /// yyyy-mm-dd, local.
  final String day;
  final DateTime at;
  final Meal meal;
  final String name;
  final int kcal;
  final FoodSource source;

  FoodEntry copyWith({String? name, int? kcal, Meal? meal}) => FoodEntry(
    id: id,
    day: day,
    at: at,
    meal: meal ?? this.meal,
    name: name ?? this.name,
    kcal: kcal ?? this.kcal,
    source: source,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'd': day,
    'at': at.millisecondsSinceEpoch,
    'm': meal.name,
    'n': name,
    'k': kcal,
    if (source != FoodSource.manual) 's': source.name,
  };

  static FoodEntry fromJson(Map<String, dynamic> j) => FoodEntry(
    id: j['id'] as String,
    day: j['d'] as String,
    at: DateTime.fromMillisecondsSinceEpoch((j['at'] as num).toInt()),
    meal: Meal.values.firstWhere(
      (m) => m.name == j['m'],
      orElse: () => Meal.snack,
    ),
    name: j['n'] as String,
    kcal: (j['k'] as num).toInt(),
    source: FoodSource.values.firstWhere(
      (s) => s.name == j['s'],
      orElse: () => FoodSource.manual,
    ),
  );
}

typedef FoodItem = ({String name, int kcal});

/// A meal you eat often, saved as its foods so one tap logs them all
/// (e.g. "My breakfast": ful, two breads, tea).
class SavedMeal {
  const SavedMeal({required this.id, required this.name, required this.items});

  final String id;
  final String name;
  final List<FoodItem> items;

  int get kcal => items.fold(0, (s, i) => s + i.kcal);

  Map<String, dynamic> toJson() => {
    'id': id,
    'n': name,
    'i': [
      for (final i in items) {'n': i.name, 'k': i.kcal},
    ],
  };

  static SavedMeal fromJson(Map<String, dynamic> j) => SavedMeal(
    id: j['id'] as String,
    name: j['n'] as String,
    items: [
      for (final i in (j['i'] as List? ?? const []))
        (name: i['n'] as String, kcal: (i['k'] as num).toInt()),
    ],
  );
}

enum Activity {
  sedentary('Mostly sitting', 1.2),
  light('Light (walks, 1–3 workouts a week)', 1.375),
  moderate('Moderate (3–5 workouts a week)', 1.55),
  active('Very active (hard work or daily training)', 1.725);

  const Activity(this.label, this.factor);

  final String label;
  final double factor;
}

enum WeightGoal {
  lose('Lose weight', -500),
  maintain('Keep my weight', 0),
  gain('Gain weight', 300);

  const WeightGoal(this.label, this.adjust);

  final String label;

  /// Calories a day added to maintenance (about ½ kg a week for −500).
  final int adjust;
}

class CalorieSettings {
  const CalorieSettings({
    this.age = 25,
    this.male = true,
    this.activity = Activity.light,
    this.goal = WeightGoal.lose,
    this.manualTarget,
  });

  final int age;
  final bool male;
  final Activity activity;
  final WeightGoal goal;

  /// Your own number instead of the calculated one.
  final int? manualTarget;

  CalorieSettings copyWith({
    int? age,
    bool? male,
    Activity? activity,
    WeightGoal? goal,
    int? manualTarget,
    bool clearManual = false,
  }) => CalorieSettings(
    age: age ?? this.age,
    male: male ?? this.male,
    activity: activity ?? this.activity,
    goal: goal ?? this.goal,
    manualTarget: clearManual ? null : manualTarget ?? this.manualTarget,
  );

  Map<String, dynamic> toJson() => {
    'age': age,
    'male': male,
    'activity': activity.name,
    'goal': goal.name,
    'manual': ?manualTarget,
  };

  static CalorieSettings fromJson(Map<String, dynamic> j) => CalorieSettings(
    age: (j['age'] as num?)?.toInt() ?? 25,
    male: j['male'] as bool? ?? true,
    activity: Activity.values.firstWhere(
      (a) => a.name == j['activity'],
      orElse: () => Activity.light,
    ),
    goal: WeightGoal.values.firstWhere(
      (g) => g.name == j['goal'],
      orElse: () => WeightGoal.lose,
    ),
    manualTarget: (j['manual'] as num?)?.toInt(),
  );
}

/// The daily target and how it was worked out.
typedef CalorieTarget = ({int target, int bmr, int maintenance, bool manual});

abstract final class CalorieMath {
  /// Mifflin–St Jeor resting energy (kcal/day).
  static double bmr({
    required double weightKg,
    required double heightCm,
    required int age,
    required bool male,
  }) => 10 * weightKg + 6.25 * heightCm - 5 * age + (male ? 5 : -161);

  static CalorieTarget target(
    CalorieSettings s, {
    required double weightKg,
    required double heightCm,
  }) {
    final rest = bmr(
      weightKg: weightKg,
      heightCm: heightCm,
      age: s.age,
      male: s.male,
    );
    final maintenance = rest * s.activity.factor;
    // Never below a safe floor when losing.
    final floor = s.male ? 1500 : 1200;
    final goal = (maintenance + s.goal.adjust).round();
    final calculated = s.goal == WeightGoal.lose && goal < floor ? floor : goal;
    return (
      target: s.manualTarget ?? _round(calculated),
      bmr: rest.round(),
      maintenance: _round(maintenance.round()),
      manual: s.manualTarget != null,
    );
  }

  static int _round(int kcal) => (kcal / 10).round() * 10;
}
