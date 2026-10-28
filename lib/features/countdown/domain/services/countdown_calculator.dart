import '../entities/countdown.dart';
import '../entities/countdown_enums.dart';

/// What a countdown looks like at a given moment.
class CountdownSnapshot {
  const CountdownSnapshot({
    required this.effectiveDate,
    required this.daysRemaining,
    required this.valueText,
    required this.label,
    required this.progress,
  });

  /// Target date after applying recurrence.
  final DateTime effectiveDate;

  /// Negative when the (non-repeating) date has passed.
  final int daysRemaining;
  final String valueText;
  final String label;

  /// 0..1 portion of the ring that is drawn.
  final double progress;

  bool get isPast => daysRemaining < 0;
}

/// Pure countdown math.
///
/// NOTE: The Android widget renderer
/// (`android/.../widgets/CountdownMath.kt`) mirrors this logic. Keep them in
/// sync when changing anything here.
abstract final class CountdownCalculator {
  static const _daysPerMonth = 30.436875;
  static const _daysPerYear = 365.2425;

  static CountdownSnapshot snapshot(Countdown countdown, {DateTime? now}) {
    final today = dateOnly(now ?? DateTime.now());
    final effective = nextOccurrence(
      countdown.targetDate,
      countdown.recurrence,
      today,
    );
    final days = daysBetween(today, effective);
    final absDays = days.abs();

    final value = switch (countdown.unit) {
      CountUnit.days => absDays.toDouble(),
      CountUnit.weeks => absDays / 7,
      CountUnit.months => absDays / _daysPerMonth,
      CountUnit.years => absDays / _daysPerYear,
    };
    final decimals = switch (countdown.unit) {
      CountUnit.days => 0,
      CountUnit.years => 2,
      _ => 1,
    };
    final valueText = formatNumber(value, decimals);

    String label;
    if (days == 0) {
      label = 'Today';
    } else {
      label = valueText == '1'
          ? countdown.unit.singularLabel
          : countdown.unit.label;
      if (days < 0) label = '$label ago';
    }

    double progress = 1;
    if (days < 0) {
      progress = 0;
    } else if (countdown.decreaseCircle) {
      final start = countdown.decreaseStartDays <= 0
          ? 1
          : countdown.decreaseStartDays;
      progress = (days / start).clamp(0.0, 1.0);
    }

    return CountdownSnapshot(
      effectiveDate: effective,
      daysRemaining: days,
      valueText: valueText,
      label: label,
      progress: progress,
    );
  }

  /// Rolls a past [target] forward according to [recurrence] so it is on or
  /// after [today].
  static DateTime nextOccurrence(
    DateTime target,
    Recurrence recurrence,
    DateTime today,
  ) {
    var date = dateOnly(target);
    if (!date.isBefore(today) || recurrence == Recurrence.none) return date;

    switch (recurrence) {
      case Recurrence.none:
        return date;
      case Recurrence.daily:
        return today;
      case Recurrence.weekly:
        final behind = daysBetween(date, today);
        final weeks = (behind / 7).ceil();
        return DateTime(date.year, date.month, date.day + weeks * 7);
      case Recurrence.monthly:
        var months = 0;
        while (date.isBefore(today)) {
          months++;
          date = addMonths(target, months);
        }
        return date;
      case Recurrence.yearly:
        var years = 0;
        while (date.isBefore(today)) {
          years++;
          date = addMonths(target, years * 12);
        }
        return date;
    }
  }

  /// Adds months while clamping the day (Jan 31 + 1 month = Feb 28/29).
  static DateTime addMonths(DateTime date, int months) {
    final monthIndex = date.month - 1 + months;
    final year = date.year + monthIndex ~/ 12;
    final month = monthIndex % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = date.day > lastDay ? lastDay : date.day;
    return DateTime(year, month, day);
  }

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Whole calendar days from [from] to [to], immune to DST shifts.
  static int daysBetween(DateTime from, DateTime to) {
    final a = DateTime.utc(from.year, from.month, from.day);
    final b = DateTime.utc(to.year, to.month, to.day);
    return b.difference(a).inDays;
  }

  /// Fixed decimals with trailing zeros removed: 26.60 -> "26.6", 3.0 -> "3".
  static String formatNumber(double value, int decimals) {
    var text = value.toStringAsFixed(decimals);
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'0+$'), '');
      text = text.replaceFirst(RegExp(r'\.$'), '');
    }
    return text;
  }
}
