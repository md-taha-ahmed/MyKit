/// Habits as "quests" (Solo Leveling style), built on habit-formation
/// research: a tiny and a full version, an anchor ("After …, I will …"),
/// if–then plans for obstacles, a weekly automaticity check, and a coach
/// that learns why a quest was missed.
library;

String habitDay(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseHabitDay(String s) {
  final [y, m, d] = s.split('-').map(int.parse).toList();
  return DateTime(y, m, d);
}

/// The stat a habit levels up.
enum HabitStat {
  strength('Strength', 'STR'),
  intelligence('Intelligence', 'INT'),
  spirit('Spirit', 'SPI'),
  discipline('Discipline', 'DIS');

  const HabitStat(this.label, this.short);

  final String label;
  final String short;
}

/// "If [situation], then I will [response]."
class IfThen {
  const IfThen(this.when, this.then);

  final String when;
  final String then;

  Map<String, dynamic> toJson() => {'if': when, 'then': then};

  static IfThen fromJson(Map<String, dynamic> j) =>
      IfThen(j['if'] as String, j['then'] as String);
}

class Habit {
  const Habit({
    required this.id,
    required this.name,
    required this.stat,
    required this.tiny,
    required this.full,
    required this.anchor,
    required this.createdAt,
    this.identity = '',
    this.outcome = '',
    this.weekdays = const {1, 2, 3, 4, 5, 6, 7},
    this.reminderMinutes,
    this.obstacles = const [],
    this.pairing = '',
    this.link,
    this.archived = false,
    this.breaking = false,
    this.lockGroups = const [],
  });

  final String id;
  final String name;
  final HabitStat stat;

  /// A habit to stop (scrolling at night…): "Clean" / "Slipped".
  final bool breaking;

  /// Screen time platforms blocked until this quest is done today.
  final List<String> lockGroups;

  /// "I'm someone who …" (who this habit makes you).
  final String identity;

  /// What it will bring (the "Outcome" of WOOP).
  final String outcome;

  /// The 2-minute version: on hard days this is the whole quest.
  final String tiny;
  final String full;

  /// "After I …" — the cue the habit follows.
  final String anchor;

  /// 1 = Monday … 7 = Sunday.
  final Set<int> weekdays;

  /// Reminder time, minutes after midnight (local time where you are).
  final int? reminderMinutes;
  final List<IfThen> obstacles;

  /// Something you enjoy, only together with the habit.
  final String pairing;

  /// Another tool that completes it automatically ('fitness').
  final String? link;
  final DateTime createdAt;
  final bool archived;

  bool dueOn(DateTime day) => !archived && weekdays.contains(day.weekday);

  Habit copyWith({
    String? name,
    HabitStat? stat,
    String? identity,
    String? outcome,
    String? tiny,
    String? full,
    String? anchor,
    Set<int>? weekdays,
    int? reminderMinutes,
    bool clearReminder = false,
    List<IfThen>? obstacles,
    String? pairing,
    String? link,
    bool clearLink = false,
    bool? archived,
    bool? breaking,
    List<String>? lockGroups,
  }) => Habit(
    id: id,
    name: name ?? this.name,
    stat: stat ?? this.stat,
    identity: identity ?? this.identity,
    outcome: outcome ?? this.outcome,
    tiny: tiny ?? this.tiny,
    full: full ?? this.full,
    anchor: anchor ?? this.anchor,
    weekdays: weekdays ?? this.weekdays,
    reminderMinutes: clearReminder
        ? null
        : reminderMinutes ?? this.reminderMinutes,
    obstacles: obstacles ?? this.obstacles,
    pairing: pairing ?? this.pairing,
    link: clearLink ? null : link ?? this.link,
    createdAt: createdAt,
    archived: archived ?? this.archived,
    breaking: breaking ?? this.breaking,
    lockGroups: lockGroups ?? this.lockGroups,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (breaking) 'breaking': true,
    if (lockGroups.isNotEmpty) 'lock': lockGroups,
    'stat': stat.name,
    'identity': identity,
    'outcome': outcome,
    'tiny': tiny,
    'full': full,
    'anchor': anchor,
    'weekdays': weekdays.toList()..sort(),
    'reminder': ?reminderMinutes,
    'obstacles': [for (final o in obstacles) o.toJson()],
    'pairing': pairing,
    'link': ?link,
    'created': createdAt.millisecondsSinceEpoch,
    if (archived) 'archived': true,
  };

  static Habit fromJson(Map<String, dynamic> j) => Habit(
    id: j['id'] as String,
    name: j['name'] as String,
    stat: HabitStat.values.firstWhere(
      (s) => s.name == j['stat'],
      orElse: () => HabitStat.discipline,
    ),
    identity: j['identity'] as String? ?? '',
    outcome: j['outcome'] as String? ?? '',
    tiny: j['tiny'] as String? ?? '',
    full: j['full'] as String? ?? '',
    anchor: j['anchor'] as String? ?? '',
    weekdays: {...((j['weekdays'] as List?) ?? const []).cast<int>()},
    reminderMinutes: (j['reminder'] as num?)?.toInt(),
    obstacles: [
      for (final o in (j['obstacles'] as List?) ?? const [])
        IfThen.fromJson(o as Map<String, dynamic>),
    ],
    pairing: j['pairing'] as String? ?? '',
    link: j['link'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (j['created'] as num).toInt(),
    ),
    archived: j['archived'] == true,
    breaking: j['breaking'] == true,
    lockGroups: ((j['lock'] as List?) ?? const []).cast<String>(),
  );
}

enum CheckStatus { full, tiny, missed, excused }

/// What got in the way, grouped by COM-B: capability, opportunity,
/// motivation — so the fix matches the kind of problem.
enum MissReason {
  forgot('Forgot', 'cue'),
  noTime('No time', 'opportunity'),
  tired('Tired / no energy', 'capability'),
  unmotivated('Didn\'t feel like it', 'motivation'),
  tooHard('Too hard / felt I can\'t', 'capability'),
  fear('Fear, doubt or a bad feeling about it', 'motivation'),
  phone('Distracted (phone…)', 'motivation'),
  noPower('No electricity', 'opportunity'),
  noInternet('No internet', 'opportunity'),
  security('Security situation', 'opportunity'),
  moved('Moved / travelling / new place', 'opportunity'),
  family('Family needed me', 'opportunity'),
  sick('Sick or in pain', 'capability'),
  other('Something else', 'other');

  const MissReason(this.label, this.kind);

  final String label;

  /// cue / capability / opportunity / motivation / other.
  final String kind;

  /// Outside your control: the day is excused, not a failure.
  bool get external => const {
    'noPower',
    'noInternet',
    'security',
    'moved',
    'family',
    'sick',
  }.contains(name);
}

class CheckIn {
  const CheckIn({
    required this.habitId,
    required this.day,
    required this.status,
    required this.at,
    this.reason,
    this.note = '',
    this.mood,
    this.auto = false,
  });

  final String habitId;

  /// yyyy-mm-dd, local.
  final String day;
  final CheckStatus status;
  final DateTime at;
  final MissReason? reason;
  final String note;

  /// 1 (very low) – 5 (great).
  final int? mood;

  /// Completed by a linked tool (a finished workout…).
  final bool auto;

  bool get done => status == CheckStatus.full || status == CheckStatus.tiny;

  CheckIn copyWith({
    CheckStatus? status,
    MissReason? reason,
    String? note,
    int? mood,
  }) => CheckIn(
    habitId: habitId,
    day: day,
    status: status ?? this.status,
    at: at,
    reason: reason ?? this.reason,
    note: note ?? this.note,
    mood: mood ?? this.mood,
    auto: auto,
  );

  Map<String, dynamic> toJson() => {
    'h': habitId,
    'd': day,
    's': status.name,
    'at': at.millisecondsSinceEpoch,
    'r': ?reason?.name,
    if (note.isNotEmpty) 'n': note,
    'm': ?mood,
    if (auto) 'auto': true,
  };

  static CheckIn fromJson(Map<String, dynamic> j) => CheckIn(
    habitId: j['h'] as String,
    day: j['d'] as String,
    status: CheckStatus.values.byName(j['s'] as String),
    at: DateTime.fromMillisecondsSinceEpoch((j['at'] as num).toInt()),
    reason: switch (j['r']) {
      final String r => MissReason.values.where((x) => x.name == r).firstOrNull,
      _ => null,
    },
    note: j['n'] as String? ?? '',
    mood: (j['m'] as num?)?.toInt(),
    auto: j['auto'] == true,
  );
}

/// The weekly 4-question automaticity check (SRBAI, 1–7 each).
class AutomaticityCheck {
  const AutomaticityCheck(this.habitId, this.date, this.scores);

  final String habitId;
  final DateTime date;
  final List<int> scores;

  double get average => scores.reduce((a, b) => a + b) / scores.length;

  Map<String, dynamic> toJson() => {
    'h': habitId,
    'at': date.millisecondsSinceEpoch,
    's': scores,
  };

  static AutomaticityCheck fromJson(Map<String, dynamic> j) =>
      AutomaticityCheck(
        j['h'] as String,
        DateTime.fromMillisecondsSinceEpoch((j['at'] as num).toInt()),
        (j['s'] as List).cast<int>(),
      );
}

/// What the System learned in a talk, and what it changed — its memory.
class CoachNote {
  const CoachNote({
    required this.habitId,
    required this.date,
    required this.insight,
    this.changes = const [],
  });

  final String habitId;
  final DateTime date;
  final String insight;

  /// The applied changes, described.
  final List<String> changes;

  Map<String, dynamic> toJson() => {
    'h': habitId,
    'at': date.millisecondsSinceEpoch,
    'i': insight,
    if (changes.isNotEmpty) 'c': changes,
  };

  static CoachNote fromJson(Map<String, dynamic> j) => CoachNote(
    habitId: j['h'] as String,
    date: DateTime.fromMillisecondsSinceEpoch((j['at'] as num).toInt()),
    insight: j['i'] as String,
    changes: ((j['c'] as List?) ?? const []).cast<String>(),
  );
}

/// One message in a talk with the System.
class CoachMessage {
  const CoachMessage({required this.fromUser, required this.text});

  final bool fromUser;
  final String text;

  Map<String, dynamic> toJson() => {'u': fromUser, 't': text};

  static CoachMessage fromJson(Map<String, dynamic> j) =>
      CoachMessage(fromUser: j['u'] == true, text: j['t'] as String);
}

/// A hard day for everything (power cut, displacement…): only tiny versions
/// are asked for and misses are excused.
class HardDay {
  const HardDay(this.day, this.reason);

  final String day;
  final MissReason reason;

  Map<String, dynamic> toJson() => {'d': day, 'r': reason.name};

  static HardDay fromJson(Map<String, dynamic> j) => HardDay(
    j['d'] as String,
    MissReason.values.firstWhere(
      (r) => r.name == j['r'],
      orElse: () => MissReason.other,
    ),
  );
}

/// The System's picture of your life (where you are, constraints, what's
/// changing). Rewritten as you tell it things; you can read and correct it.
class LifeContext {
  const LifeContext({this.summary = '', this.updatedAt, this.lastAskedAt});

  final String summary;
  final DateTime? updatedAt;

  /// When the weekly "anything changed?" question was last asked.
  final DateTime? lastAskedAt;

  LifeContext copyWith({
    String? summary,
    DateTime? updatedAt,
    DateTime? lastAskedAt,
  }) => LifeContext(
    summary: summary ?? this.summary,
    updatedAt: updatedAt ?? this.updatedAt,
    lastAskedAt: lastAskedAt ?? this.lastAskedAt,
  );

  Map<String, dynamic> toJson() => {
    's': summary,
    'u': ?updatedAt?.millisecondsSinceEpoch,
    'a': ?lastAskedAt?.millisecondsSinceEpoch,
  };

  static LifeContext fromJson(Map<String, dynamic> j) => LifeContext(
    summary: j['s'] as String? ?? '',
    updatedAt: switch (j['u']) {
      final num n => DateTime.fromMillisecondsSinceEpoch(n.toInt()),
      _ => null,
    },
    lastAskedAt: switch (j['a']) {
      final num n => DateTime.fromMillisecondsSinceEpoch(n.toInt()),
      _ => null,
    },
  );
}

/// What the System understands about one habit: why you get stuck, what
/// helps, what doesn't. Sharpened after every talk instead of piling up.
class HabitUnderstanding {
  const HabitUnderstanding({
    this.rootCause = '',
    this.evidence = '',
    this.helps = '',
    this.fails = '',
    this.confidence = 0,
    this.updatedAt,
  });

  /// The real reason you're stuck (practical or emotional).
  final String rootCause;

  /// What in your history points to it.
  final String evidence;
  final String helps;
  final String fails;

  /// 0–100: how sure the System is.
  final int confidence;
  final DateTime? updatedAt;

  bool get isEmpty => rootCause.isEmpty && helps.isEmpty && fails.isEmpty;

  Map<String, dynamic> toJson() => {
    'root': rootCause,
    'evidence': evidence,
    'helps': helps,
    'fails': fails,
    'conf': confidence,
    'u': ?updatedAt?.millisecondsSinceEpoch,
  };

  static HabitUnderstanding fromJson(Map<String, dynamic> j) =>
      HabitUnderstanding(
        rootCause: j['root'] as String? ?? '',
        evidence: j['evidence'] as String? ?? '',
        helps: j['helps'] as String? ?? '',
        fails: j['fails'] as String? ?? '',
        confidence: (j['conf'] as num?)?.toInt() ?? 0,
        updatedAt: switch (j['u']) {
          final num n => DateTime.fromMillisecondsSinceEpoch(n.toInt()),
          _ => null,
        },
      );
}

/// A to-do. It can come from you or be suggested by the System.
class HabitTask {
  const HabitTask({
    required this.id,
    required this.title,
    required this.createdAt,
    this.note = '',
    this.due,
    this.doneAt,
    this.fromSystem = false,
  });

  final String id;
  final String title;
  final String note;

  /// yyyy-mm-dd, or none.
  final String? due;
  final DateTime createdAt;
  final DateTime? doneAt;
  final bool fromSystem;

  bool get done => doneAt != null;

  bool overdue(DateTime now) =>
      !done && due != null && due!.compareTo(habitDay(now)) < 0;

  HabitTask copyWith({
    String? title,
    String? note,
    String? due,
    bool clearDue = false,
    DateTime? doneAt,
    bool clearDone = false,
  }) => HabitTask(
    id: id,
    title: title ?? this.title,
    note: note ?? this.note,
    due: clearDue ? null : due ?? this.due,
    createdAt: createdAt,
    doneAt: clearDone ? null : doneAt ?? this.doneAt,
    fromSystem: fromSystem,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    't': title,
    if (note.isNotEmpty) 'n': note,
    'due': ?due,
    'c': createdAt.millisecondsSinceEpoch,
    'done': ?doneAt?.millisecondsSinceEpoch,
    if (fromSystem) 'sys': true,
  };

  static HabitTask fromJson(Map<String, dynamic> j) => HabitTask(
    id: j['id'] as String,
    title: j['t'] as String,
    note: j['n'] as String? ?? '',
    due: j['due'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch((j['c'] as num).toInt()),
    doneAt: switch (j['done']) {
      final num n => DateTime.fromMillisecondsSinceEpoch(n.toInt()),
      _ => null,
    },
    fromSystem: j['sys'] == true,
  );
}

/// Something that helps when a feeling hits — written by you.
class AidAction {
  const AidAction(this.id, this.text);

  final String id;
  final String text;

  Map<String, dynamic> toJson() => {'id': id, 't': text};

  static AidAction fromJson(Map<String, dynamic> j) =>
      AidAction(j['id'] as String, j['t'] as String);
}

/// One page of your aid kit: a feeling and what helps with it.
class AidEntry {
  const AidEntry({
    required this.id,
    required this.feeling,
    this.emoji = '🩹',
    this.actions = const [],
  });

  final String id;

  /// "Overstimulated", "Urge to scroll"…
  final String feeling;
  final String emoji;
  final List<AidAction> actions;

  AidEntry copyWith({
    String? feeling,
    String? emoji,
    List<AidAction>? actions,
  }) => AidEntry(
    id: id,
    feeling: feeling ?? this.feeling,
    emoji: emoji ?? this.emoji,
    actions: actions ?? this.actions,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'f': feeling,
    'e': emoji,
    'a': [for (final a in actions) a.toJson()],
  };

  static AidEntry fromJson(Map<String, dynamic> j) => AidEntry(
    id: j['id'] as String,
    feeling: j['f'] as String,
    emoji: j['e'] as String? ?? '🩹',
    actions: [
      for (final a in (j['a'] as List?) ?? const [])
        AidAction.fromJson(a as Map<String, dynamic>),
    ],
  );
}

/// You used the aid kit: what you felt, what you did, and if it helped.
class AidUse {
  const AidUse({
    required this.entryId,
    required this.actionId,
    required this.at,
    this.helped,
  });

  final String entryId;
  final String actionId;
  final DateTime at;

  /// null until you say.
  final bool? helped;

  AidUse withHelped(bool v) =>
      AidUse(entryId: entryId, actionId: actionId, at: at, helped: v);

  Map<String, dynamic> toJson() => {
    'e': entryId,
    'a': actionId,
    'at': at.millisecondsSinceEpoch,
    'h': ?helped,
  };

  static AidUse fromJson(Map<String, dynamic> j) => AidUse(
    entryId: j['e'] as String,
    actionId: j['a'] as String,
    at: DateTime.fromMillisecondsSinceEpoch((j['at'] as num).toInt()),
    helped: j['h'] as bool?,
  );
}

/// One day across the app, kept for patterns (about four months).
class DaySnapshot {
  const DaySnapshot({
    required this.day,
    this.socialMinutes,
    this.kcal = 0,
    this.kcalTarget,
    this.meals = 0,
    this.lessonRead = false,
    this.workoutPlanned = false,
    this.workoutDone = false,
    this.questsDue = 0,
    this.questsDone = 0,
    this.mood,
    this.hard = false,
  });

  final String day;

  /// Social media minutes (Screen time), when known.
  final int? socialMinutes;
  final int kcal;
  final int? kcalTarget;
  final int meals;
  final bool lessonRead;
  final bool workoutPlanned;
  final bool workoutDone;
  final int questsDue;
  final int questsDone;

  /// Average mood given in check-ins (1–5).
  final double? mood;
  final bool hard;

  DaySnapshot copyWith({int? socialMinutes, int? kcalTarget}) => DaySnapshot(
    day: day,
    socialMinutes: socialMinutes ?? this.socialMinutes,
    kcal: kcal,
    kcalTarget: kcalTarget ?? this.kcalTarget,
    meals: meals,
    lessonRead: lessonRead,
    workoutPlanned: workoutPlanned,
    workoutDone: workoutDone,
    questsDue: questsDue,
    questsDone: questsDone,
    mood: mood,
    hard: hard,
  );

  Map<String, dynamic> toJson() => {
    'd': day,
    'soc': ?socialMinutes,
    'k': kcal,
    'kt': ?kcalTarget,
    'm': meals,
    if (lessonRead) 'l': true,
    if (workoutPlanned) 'wp': true,
    if (workoutDone) 'wd': true,
    'qd': questsDue,
    'qn': questsDone,
    'mood': ?mood,
    if (hard) 'h': true,
  };

  static DaySnapshot fromJson(Map<String, dynamic> j) => DaySnapshot(
    day: j['d'] as String,
    socialMinutes: (j['soc'] as num?)?.toInt(),
    kcal: (j['k'] as num?)?.toInt() ?? 0,
    kcalTarget: (j['kt'] as num?)?.toInt(),
    meals: (j['m'] as num?)?.toInt() ?? 0,
    lessonRead: j['l'] == true,
    workoutPlanned: j['wp'] == true,
    workoutDone: j['wd'] == true,
    questsDue: (j['qd'] as num?)?.toInt() ?? 0,
    questsDone: (j['qn'] as num?)?.toInt() ?? 0,
    mood: (j['mood'] as num?)?.toDouble(),
    hard: j['h'] == true,
  );
}

/// The System's weekly review.
class WeeklyReview {
  const WeeklyReview({
    required this.date,
    required this.text,
    this.experiment = '',
  });

  final DateTime date;
  final String text;

  /// One thing to try next week.
  final String experiment;

  Map<String, dynamic> toJson() => {
    'at': date.millisecondsSinceEpoch,
    't': text,
    'x': experiment,
  };

  static WeeklyReview fromJson(Map<String, dynamic> j) => WeeklyReview(
    date: DateTime.fromMillisecondsSinceEpoch((j['at'] as num).toInt()),
    text: j['t'] as String,
    experiment: j['x'] as String? ?? '',
  );
}
