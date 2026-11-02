import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/ai/gemini_client.dart';
import '../../../../core/storage/shared_preferences_provider.dart';
import '../../data/food_estimator.dart';
import '../../domain/food.dart';
import 'fitness_providers.dart';

String foodDay(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Everything eaten (about a year), newest first. In the Drive backup.
final foodLogProvider = NotifierProvider<FoodLogNotifier, List<FoodEntry>>(
  FoodLogNotifier.new,
);

class FoodLogNotifier extends Notifier<List<FoodEntry>> {
  static const _key = 'fitness.food.v1';
  static const _keep = 4000;

  @override
  List<FoodEntry> build() {
    final raw = ref.read(sharedPreferencesProvider).getString(_key);
    if (raw == null) return const [];
    try {
      return [
        for (final j in jsonDecode(raw) as List)
          FoodEntry.fromJson(j as Map<String, dynamic>),
      ]..sort((a, b) => b.at.compareTo(a.at));
    } catch (_) {
      return const [];
    }
  }

  Future<void> _save(List<FoodEntry> v) async {
    state = v;
    await ref
        .read(sharedPreferencesProvider)
        .setString(
          _key,
          jsonEncode([for (final e in v.take(_keep)) e.toJson()]),
        );
  }

  Future<void> add(
    String name,
    int kcal, {
    Meal? meal,
    FoodSource source = FoodSource.manual,
    DateTime? at,
  }) {
    final when = at ?? DateTime.now();
    return _save([
      FoodEntry(
        id: const Uuid().v4(),
        day: foodDay(when),
        at: when,
        meal: meal ?? Meal.forTime(when),
        name: name.trim(),
        kcal: kcal,
        source: source,
      ),
      ...state,
    ]);
  }

  Future<void> update(FoodEntry entry) =>
      _save([for (final e in state) e.id == entry.id ? entry : e]);

  Future<void> remove(String id) =>
      _save(state.where((e) => e.id != id).toList());

  /// Logs every food of a saved meal.
  Future<void> addMeal(SavedMeal saved, {Meal? meal}) {
    final when = DateTime.now();
    return _save([
      for (final (n, i) in saved.items.indexed)
        FoodEntry(
          id: const Uuid().v4(),
          day: foodDay(when),
          // Keeps the meal's order in the list (newest first).
          at: when.add(Duration(milliseconds: saved.items.length - n)),
          meal: meal ?? Meal.forTime(when),
          name: i.name,
          kcal: i.kcal,
        ),
      ...state,
    ]);
  }

  /// Foods logged before, most recent first, for one-tap re-adding.
  List<FoodItem> get recent {
    final seen = <String>{};
    return [
      for (final e in state)
        if (seen.add(e.name.toLowerCase())) (name: e.name, kcal: e.kcal),
    ].take(24).toList();
  }
}

/// Meals you saved (several foods logged with one tap). In the Drive backup.
final savedMealsProvider =
    NotifierProvider<SavedMealsNotifier, List<SavedMeal>>(
      SavedMealsNotifier.new,
    );

class SavedMealsNotifier extends Notifier<List<SavedMeal>> {
  static const _key = 'fitness.food.meals.v1';

  @override
  List<SavedMeal> build() {
    final raw = ref.read(sharedPreferencesProvider).getString(_key);
    if (raw == null) return const [];
    try {
      return [
        for (final j in jsonDecode(raw) as List)
          SavedMeal.fromJson(j as Map<String, dynamic>),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _save(List<SavedMeal> v) async {
    state = v;
    await ref
        .read(sharedPreferencesProvider)
        .setString(_key, jsonEncode([for (final m in v) m.toJson()]));
  }

  /// Adds [meal], or replaces the one with its id.
  Future<void> save(SavedMeal meal) => _save([
    if (!state.any((m) => m.id == meal.id)) meal,
    for (final m in state) m.id == meal.id ? meal : m,
  ]);

  Future<void> remove(String id) =>
      _save(state.where((m) => m.id != id).toList());
}

/// Calories eaten per day.
final caloriesByDayProvider = Provider<Map<String, int>>((ref) {
  final out = <String, int>{};
  for (final e in ref.watch(foodLogProvider)) {
    out[e.day] = (out[e.day] ?? 0) + e.kcal;
  }
  return out;
});

final calorieSettingsProvider =
    NotifierProvider<CalorieSettingsNotifier, CalorieSettings>(
      CalorieSettingsNotifier.new,
    );

class CalorieSettingsNotifier extends Notifier<CalorieSettings> {
  static const _key = 'fitness.calories.v1';

  @override
  CalorieSettings build() {
    final raw = ref.read(sharedPreferencesProvider).getString(_key);
    if (raw == null) return const CalorieSettings();
    try {
      return CalorieSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const CalorieSettings();
    }
  }

  Future<void> update(CalorieSettings s) async {
    state = s;
    await ref
        .read(sharedPreferencesProvider)
        .setString(_key, jsonEncode(s.toJson()));
  }
}

/// Your latest logged weight (or the starting weight from the profile).
final currentWeightProvider = Provider<double>((ref) {
  final log = ref.watch(bodyLogProvider);
  for (final e in log.reversed) {
    if (e.weightKg case final w?) return w;
  }
  return ref.watch(fitnessProfileProvider).startWeightKg;
});

final calorieTargetProvider = Provider<CalorieTarget>(
  (ref) => CalorieMath.target(
    ref.watch(calorieSettingsProvider),
    weightKg: ref.watch(currentWeightProvider),
    heightCm: ref.watch(fitnessProfileProvider).heightCm,
  ),
);

final foodEstimatorProvider = Provider<FoodEstimator>(
  (ref) => FoodEstimator(ref.watch(geminiClientProvider)),
);
