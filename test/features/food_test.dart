import 'package:flutter_test/flutter_test.dart';
import 'package:mykit/core/ai/gemini_client.dart';
import 'package:mykit/features/fitness/data/food_estimator.dart';
import 'package:mykit/features/fitness/domain/food.dart';

void main() {
  test('target from weight and height (Mifflin–St Jeor)', () {
    // 100 kg, 181 cm, 25, male: BMR = 1000 + 1131.25 − 125 + 5 = 2011.
    final t = CalorieMath.target(
      const CalorieSettings(age: 25, activity: Activity.light),
      weightKg: 100,
      heightCm: 181,
    );
    expect(t.bmr, 2011);
    expect(t.maintenance, 2770); // 2011 × 1.375 ≈ 2765 → 2770
    expect(t.target, 2270); // −500 to lose
    expect(t.manual, isFalse);
  });

  test('never below a safe floor; a manual target wins', () {
    final low = CalorieMath.target(
      const CalorieSettings(age: 60, male: false, activity: Activity.sedentary),
      weightKg: 45,
      heightCm: 150,
    );
    expect(low.target, 1200);
    final manual = CalorieMath.target(
      const CalorieSettings(manualTarget: 1800),
      weightKg: 100,
      heightCm: 181,
    );
    expect(manual.target, 1800);
    expect(manual.manual, isTrue);
  });

  test('reads the estimate, even wrapped in text', () {
    final e = FoodEstimator.parse(
      '''
Here you go:
{"items":[{"name":"سلتة","amount":"1 bowl","kcal":420},{"name":"Bread","amount":"2","kcal":360}],"note":"Assumed ghee."}''',
    );
    expect(e.items, hasLength(2));
    expect(e.total, 780);
    expect(e.note, 'Assumed ghee.');
    expect(() => FoodEstimator.parse('no json'), throwsA(isA<AiException>()));
  });

  test('meal follows the time of day', () {
    expect(Meal.forTime(DateTime(2026, 1, 1, 8)), Meal.breakfast);
    expect(Meal.forTime(DateTime(2026, 1, 1, 14)), Meal.lunch);
    expect(Meal.forTime(DateTime(2026, 1, 1, 19)), Meal.dinner);
    expect(Meal.forTime(DateTime(2026, 1, 1, 23)), Meal.snack);
  });

  test('saved meals keep their foods and total', () {
    const m = SavedMeal(
      id: 'm',
      name: 'Breakfast',
      items: [(name: 'Ful', kcal: 350), (name: 'Bread', kcal: 250)],
    );
    final back = SavedMeal.fromJson(m.toJson());
    expect(back.items.length, 2);
    expect(back.kcal, 600);
    expect(back.items.first.name, 'Ful');
  });

  test('editing a food keeps its day and source', () {
    final e = FoodEntry(
      id: '1',
      day: '2026-11-02',
      at: DateTime(2026, 11, 2, 8),
      meal: Meal.breakfast,
      name: 'Tea',
      kcal: 40,
      source: FoodSource.photo,
    );
    final edited = e.copyWith(kcal: 90, meal: Meal.snack);
    expect(edited.kcal, 90);
    expect(edited.meal, Meal.snack);
    expect(edited.day, e.day);
    expect(edited.source, FoodSource.photo);
  });
}
