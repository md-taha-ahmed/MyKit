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
    final e = FoodEstimator.parse('''
Here you go:
{"items":[{"name":"سلتة","amount":"1 bowl","kcal":420},{"name":"Bread","amount":"2","kcal":360}],"note":"Assumed ghee."}''');
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
}
