import 'package:flutter_test/flutter_test.dart';
import 'package:mykit/features/countdown/data/models/countdown_model.dart';
import 'package:mykit/features/countdown/domain/entities/countdown.dart';
import 'package:mykit/features/countdown/domain/entities/countdown_enums.dart';
import 'package:mykit/features/countdown/domain/services/countdown_calculator.dart';

Countdown _countdown(
  DateTime target, {
  CountUnit unit = CountUnit.days,
  Recurrence recurrence = Recurrence.none,
  int startDays = 30,
}) => Countdown(
  id: 'x',
  targetDate: target,
  createdAt: DateTime(2026),
  unit: unit,
  recurrence: recurrence,
  decreaseStartDays: startDays,
);

void main() {
  final now = DateTime(2026, 10, 27, 6);

  test('matches the reference screenshot: 1 May 2027 → 26.6 weeks', () {
    final snap = CountdownCalculator.snapshot(
      _countdown(DateTime(2027, 5, 1), unit: CountUnit.weeks, startDays: 187),
      now: now,
    );
    expect(snap.daysRemaining, 186);
    expect(snap.valueText, '26.6');
    expect(snap.label, 'Weeks');
    expect(snap.progress, closeTo(186 / 187, 1e-9));
  });

  test('today and past dates', () {
    final today = CountdownCalculator.snapshot(
      _countdown(DateTime(2026, 10, 27)),
      now: now,
    );
    expect(today.label, 'Today');
    expect(today.progress, 0);

    final past = CountdownCalculator.snapshot(
      _countdown(DateTime(2026, 10, 26)),
      now: now,
    );
    expect(past.valueText, '1');
    expect(past.label, 'Day ago');
  });

  test('recurrence rolls past dates forward', () {
    DateTime next(DateTime d, Recurrence r) =>
        CountdownCalculator.nextOccurrence(d, r, DateTime(2026, 10, 27));

    expect(
      next(DateTime(2026, 10, 20), Recurrence.weekly),
      DateTime(2026, 10, 27),
    );
    expect(
      next(DateTime(2026, 1, 31), Recurrence.monthly),
      DateTime(2026, 10, 31),
    );
    expect(
      next(DateTime(2000, 3, 15), Recurrence.yearly),
      DateTime(2027, 3, 15),
    );
    expect(
      next(DateTime(2020, 2, 29), Recurrence.yearly),
      DateTime(2027, 2, 28),
    );
  });

  test('json round trip', () {
    final original = _countdown(
      DateTime(2027, 5, 1),
      unit: CountUnit.months,
    ).copyWith(title: 'Trip', ringColor: 0xFF123456, clockwise: true);
    final copy = CountdownModel.fromJson(CountdownModel.toJson(original));
    expect(copy.title, 'Trip');
    expect(copy.targetDate, DateTime(2027, 5, 1));
    expect(copy.unit, CountUnit.months);
    expect(copy.ringColor, 0xFF123456);
    expect(copy.clockwise, isTrue);
  });
}
