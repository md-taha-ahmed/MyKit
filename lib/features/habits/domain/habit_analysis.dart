import 'habit_models.dart';

/// Ranks follow how automatic a habit feels (the weekly check), not streaks:
/// automaticity is what a habit is.
enum HabitRank { e, d, c, b, a, s }

extension HabitRankLabel on HabitRank {
  String get letter => name.toUpperCase();
}

/// Numbers behind the quests: XP and levels, streaks, rates, reasons.
/// Everything is computed on the phone from the check-ins.
abstract final class HabitAnalysis {
  static const fullXp = 10;
  static const tinyXp = 6;

  /// Doing it the day after a miss ("never miss twice").
  static const recoveryBonus = 5;

  /// Showing up again after a hard day.
  static const resilienceBonus = 3;
  static const weeklyCheckXp = 5;

  static int xpOf(CheckIn c) => switch (c.status) {
    CheckStatus.full => fullXp,
    CheckStatus.tiny => tinyXp,
    _ => 0,
  };

  /// All XP: check-ins, recoveries, comebacks and weekly checks.
  static int totalXp(
    List<CheckIn> checks,
    List<AutomaticityCheck> weekly,
    Set<String> hardDays,
  ) {
    var xp = weekly.length * weeklyCheckXp;
    final byHabit = <String, List<CheckIn>>{};
    for (final c in checks) {
      byHabit.putIfAbsent(c.habitId, () => []).add(c);
    }
    for (final list in byHabit.values) {
      list.sort((a, b) => a.day.compareTo(b.day));
      CheckIn? previous;
      for (final c in list) {
        xp += xpOf(c);
        if (c.done && previous != null) {
          if (previous.status == CheckStatus.missed) xp += recoveryBonus;
          if (previous.status == CheckStatus.excused ||
              hardDays.contains(previous.day)) {
            xp += resilienceBonus;
          }
        }
        previous = c;
      }
    }
    return xp;
  }

  /// XP to go from level [level] to the next.
  static int xpForLevel(int level) => 50 + 25 * (level - 1);

  /// Level (from 1) and the XP into it.
  static ({int level, int into, int needed}) level(int xp) {
    var level = 1;
    var left = xp;
    while (left >= xpForLevel(level)) {
      left -= xpForLevel(level);
      level++;
    }
    return (level: level, into: left, needed: xpForLevel(level));
  }

  /// Points per stat: the XP of the habits that train it.
  static Map<HabitStat, int> stats(List<Habit> habits, List<CheckIn> checks) {
    final statOf = {for (final h in habits) h.id: h.stat};
    final out = {for (final s in HabitStat.values) s: 0};
    for (final c in checks) {
      final s = statOf[c.habitId];
      if (s != null) out[s] = out[s]! + xpOf(c);
    }
    return out;
  }

  static HabitRank rank(List<AutomaticityCheck> checks, Habit habit) {
    if (checks.isEmpty) return HabitRank.e;
    final sorted = [...checks]..sort((a, b) => a.date.compareTo(b.date));
    final avg = sorted.last.average;
    final days = DateTime.now().difference(habit.createdAt).inDays;
    final strong = sorted.where((c) => c.average >= 6).length;
    if (avg >= 6 && strong >= 2 && days >= 60) return HabitRank.s;
    if (avg >= 6) return HabitRank.a;
    if (avg >= 5) return HabitRank.b;
    if (avg >= 4) return HabitRank.c;
    if (avg >= 3) return HabitRank.d;
    return HabitRank.e;
  }

  /// Due days of [habit] from [from] to [to] (inclusive), newest first.
  static List<DateTime> dueDays(Habit habit, DateTime from, DateTime to) {
    final out = <DateTime>[];
    var d = DateTime(to.year, to.month, to.day);
    final start = DateTime(from.year, from.month, from.day);
    while (!d.isBefore(start)) {
      if (habit.weekdays.contains(d.weekday)) out.add(d);
      d = d.subtract(const Duration(days: 1));
    }
    return out;
  }

  /// Consecutive due days done (newest first). Excused and hard days don't
  /// break it; today doesn't count until checked.
  static int streak(
    Habit habit,
    Map<String, CheckIn> checks,
    Set<String> hardDays, {
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    var n = 0;
    for (final d in dueDays(habit, habit.createdAt, today)) {
      final key = habitDay(d);
      final c = checks[key];
      if (c == null && key == habitDay(today)) continue;
      if (c != null && c.done) {
        n++;
      } else if (c?.status == CheckStatus.excused || hardDays.contains(key)) {
        continue;
      } else {
        break;
      }
    }
    return n;
  }

  /// The last due day before today was missed: today is a recovery quest.
  static bool recoveryToday(
    Habit habit,
    Map<String, CheckIn> checks, {
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final days = dueDays(
      habit,
      today.subtract(const Duration(days: 8)),
      today.subtract(const Duration(days: 1)),
    );
    if (days.isEmpty) return false;
    return checks[habitDay(days.first)]?.status == CheckStatus.missed;
  }

  /// Done / (done + missed) over the last [days] days; excused days and
  /// unanswered ones are left out. Null without data.
  static double? rate(Iterable<CheckIn> checks, {int days = 30}) {
    final since = habitDay(DateTime.now().subtract(Duration(days: days)));
    var done = 0, missed = 0;
    for (final c in checks) {
      if (c.day.compareTo(since) < 0) continue;
      if (c.done) done++;
      if (c.status == CheckStatus.missed) missed++;
    }
    final total = done + missed;
    return total == 0 ? null : done / total;
  }

  /// How often each reason was given, most common first.
  static List<(MissReason, int)> reasons(Iterable<CheckIn> checks) {
    final count = <MissReason, int>{};
    for (final c in checks) {
      if (c.reason case final r?) count[r] = (count[r] ?? 0) + 1;
    }
    return count.entries.map((e) => (e.key, e.value)).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
  }

  /// Success rate per weekday (1–7), where there's data.
  static Map<int, double> byWeekday(Iterable<CheckIn> checks) {
    final done = <int, int>{}, all = <int, int>{};
    for (final c in checks) {
      if (c.status == CheckStatus.excused) continue;
      final wd = parseHabitDay(c.day).weekday;
      all[wd] = (all[wd] ?? 0) + 1;
      if (c.done) done[wd] = (done[wd] ?? 0) + 1;
    }
    return {for (final e in all.entries) e.key: (done[e.key] ?? 0) / e.value};
  }

  /// A plain-language fix for the most common kind of reason (COM-B).
  static String? adviceFor(MissReason reason) => switch (reason.kind) {
    'cue' =>
      'Forgetting is a cue problem, not a willpower one. Tie it to something you never skip, like a prayer, and keep what you need in sight.',
    'capability' =>
      'It asks too much on those days. Make the tiny version even smaller, or move it to when you have more energy.',
    'opportunity' =>
      'Life around you got in the way. Plan a version that still works then: a no-power version, a travel version, a 2-minute version.',
    'motivation' =>
      'The feeling about it is the obstacle. Talk it through with the System, pair it with something you enjoy, and remember why you started.',
    _ => null,
  };
}
