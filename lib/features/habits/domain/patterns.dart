import 'habit_models.dart';

/// A pattern found in your own days: how something differs on heavy days.
class DayPattern {
  const DayPattern({
    required this.text,
    required this.onHeavy,
    required this.onNormal,
    required this.heavyDays,
    required this.normalDays,
  });

  /// An English key for tr(): "{what} on heavy-scrolling days".
  final String text;

  /// Rates 0–1 on heavy and normal days.
  final double onHeavy;
  final double onNormal;
  final int heavyDays;
  final int normalDays;
}

/// Patterns across your days. Screen time is the "down" signal: a heavy day
/// is one with much more social media than your usual (1.5× your median).
/// Only shown with enough days on both sides — they are correlations, not
/// causes.
abstract final class DayPatterns {
  static const _minDays = 3;

  /// Your usual social-media minutes (median of days with data).
  static int? usualSocial(List<DaySnapshot> days) {
    final m = [
      for (final d in days)
        if ((d.socialMinutes ?? 0) > 0) d.socialMinutes!,
    ]..sort();
    if (m.length < 5) return null;
    return m[m.length ~/ 2];
  }

  static bool heavy(DaySnapshot d, int usual) =>
      (d.socialMinutes ?? 0) >= (usual * 1.5).round() &&
      (d.socialMinutes ?? 0) >= 30;

  static List<DayPattern> find(List<DaySnapshot> days) {
    final usual = usualSocial(days);
    if (usual == null) return const [];
    final known = days.where((d) => d.socialMinutes != null).toList();
    final heavyDays = known.where((d) => heavy(d, usual)).toList();
    final normalDays = known.where((d) => !heavy(d, usual)).toList();

    DayPattern? compare(
      String text,
      bool Function(DaySnapshot) counts,
      bool Function(DaySnapshot) yes,
    ) {
      final h = heavyDays.where(counts).toList();
      final n = normalDays.where(counts).toList();
      if (h.length < _minDays || n.length < _minDays) return null;
      final rh = h.where(yes).length / h.length;
      final rn = n.where(yes).length / n.length;
      if ((rh - rn).abs() < 0.2) return null;
      return DayPattern(
        text: text,
        onHeavy: rh,
        onNormal: rn,
        heavyDays: h.length,
        normalDays: n.length,
      );
    }

    return [
      ?compare('Workout done', (d) => d.workoutPlanned, (d) => d.workoutDone),
      ?compare(
        'Ate over your target',
        (d) => d.kcalTarget != null && d.meals > 0,
        (d) => d.kcal > d.kcalTarget!,
      ),
      ?compare(
        'All quests done',
        (d) => d.questsDue > 0,
        (d) => d.questsDone >= d.questsDue,
      ),
      ?compare('Lesson read', (_) => true, (d) => d.lessonRead),
      ?compare('Low mood (1–2)', (d) => d.mood != null, (d) => d.mood! <= 2),
    ];
  }

  /// When you actually do a habit: the median time of your done check-ins
  /// (last 21 days, at least 5), in minutes after midnight.
  static int? typicalTime(Iterable<CheckIn> checks, {DateTime? now}) {
    final since = (now ?? DateTime.now()).subtract(const Duration(days: 21));
    final times = [
      for (final c in checks)
        if (c.done && !c.auto && c.at.isAfter(since))
          c.at.hour * 60 + c.at.minute,
    ]..sort();
    if (times.length < 5) return null;
    return times[times.length ~/ 2];
  }
}

/// The tabular Islamic calendar (±1 day of the sighted one).
abstract final class Hijri {
  static const months = [
    'Muharram',
    'Safar',
    'Rabi al-Awwal',
    'Rabi al-Thani',
    'Jumada al-Ula',
    'Jumada al-Akhirah',
    'Rajab',
    'Shaban',
    'Ramadan',
    'Shawwal',
    'Dhu al-Qadah',
    'Dhu al-Hijjah',
  ];

  static ({int year, int month, int day}) of(DateTime g) {
    // Julian day number of the Gregorian date.
    final a = (14 - g.month) ~/ 12;
    final y = g.year + 4800 - a;
    final m = g.month + 12 * a - 3;
    final jd =
        g.day +
        (153 * m + 2) ~/ 5 +
        365 * y +
        y ~/ 4 -
        y ~/ 100 +
        y ~/ 400 -
        32045;
    // Islamic from the Julian day (Kuwaiti algorithm).
    var l = jd - 1948440 + 10632;
    final n = (l - 1) ~/ 10631;
    l = l - 10631 * n + 354;
    final j =
        ((10985 - l) ~/ 5316) * ((50 * l) ~/ 17719) +
        (l ~/ 5670) * ((43 * l) ~/ 15238);
    l =
        l -
        ((30 - j) ~/ 15) * ((17719 * j) ~/ 50) -
        (j ~/ 16) * ((15238 * j) ~/ 43) +
        29;
    final month = (24 * l) ~/ 709;
    final day = l - (709 * month) ~/ 24;
    final year = 30 * n + j - 30;
    return (year: year, month: month, day: day);
  }
}

/// A natural new beginning today, if any: research shows people act on goals
/// more after "fresh starts" (new week, month, year).
String? freshStart(DateTime now) {
  final h = Hijri.of(now);
  if (h.month == 9 && h.day <= 3) return 'Ramadan';
  if (h.day == 1) return 'new Hijri month';
  if (now.day == 1) return 'new month';
  if (now.weekday == DateTime.saturday) return 'new week';
  return null;
}
