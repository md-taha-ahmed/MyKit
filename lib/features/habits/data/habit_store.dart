import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/habit_models.dart';
import 'tasks_sync.dart';

/// Habits, check-ins and what the System knows, in SharedPreferences (so the
/// Drive backup includes them). Works fully offline.
class HabitStore {
  HabitStore(this._prefs);

  final SharedPreferences _prefs;

  static const _habits = 'habits.list.v1';
  static const _checks = 'habits.checkins.v1';
  static const _weekly = 'habits.weekly.v1';
  static const _notes = 'habits.notes.v1';
  static const _understanding = 'habits.understanding.v1';
  static const _life = 'habits.life.v1';
  static const _hardDays = 'habits.hardDays.v1';
  static const _talks = 'habits.talks.v1';
  static const _tasks = 'habits.tasks.v1';
  static const _taskLists = 'habits.taskLists.v1';
  static const _tasksGone = 'habits.tasks.gone.v1';
  // v2: the first v1 pull missed open tasks, so pull everything once more.
  static const _tasksSynced = 'habits.tasks.synced.v2';
  static const _aid = 'habits.aidKit.v1';
  static const _aidUses = 'habits.aidUses.v1';
  static const _days = 'habits.days.v1';
  static const _reviews = 'habits.reviews.v1';
  static const _flags = 'habits.flags.v1';

  /// Check-ins kept per habit (about two years of daily ones).
  static const _checksPerHabit = 730;
  static const _notesPerHabit = 30;

  Object? _json(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> _put(String key, Object value) =>
      _prefs.setString(key, jsonEncode(value));

  List<T> _list<T>(String key, T Function(Map<String, dynamic>) read) => [
    for (final j in (_json(key) as List?) ?? const [])
      ?_try(() => read(j as Map<String, dynamic>)),
  ];

  static T? _try<T>(T Function() f) {
    try {
      return f();
    } catch (_) {
      return null;
    }
  }

  List<Habit> get habits => _list(_habits, Habit.fromJson);

  Future<void> saveHabits(List<Habit> v) =>
      _put(_habits, [for (final h in v) h.toJson()]);

  List<CheckIn> get checkIns => _list(_checks, CheckIn.fromJson);

  Future<void> saveCheckIns(List<CheckIn> v) {
    final byHabit = <String, List<CheckIn>>{};
    for (final c in v) {
      byHabit.putIfAbsent(c.habitId, () => []).add(c);
    }
    final kept = [
      for (final list in byHabit.values)
        ...(list..sort((a, b) => b.day.compareTo(a.day))).take(_checksPerHabit),
    ];
    return _put(_checks, [for (final c in kept) c.toJson()]);
  }

  List<AutomaticityCheck> get weekly =>
      _list(_weekly, AutomaticityCheck.fromJson);

  Future<void> saveWeekly(List<AutomaticityCheck> v) =>
      _put(_weekly, [for (final c in v) c.toJson()]);

  List<CoachNote> get notes => _list(_notes, CoachNote.fromJson);

  Future<void> saveNotes(List<CoachNote> v) {
    final byHabit = <String, List<CoachNote>>{};
    for (final n in v) {
      byHabit.putIfAbsent(n.habitId, () => []).add(n);
    }
    final kept = [
      for (final list in byHabit.values)
        ...(list..sort((a, b) => b.date.compareTo(a.date))).take(
          _notesPerHabit,
        ),
    ];
    return _put(_notes, [for (final n in kept) n.toJson()]);
  }

  Map<String, HabitUnderstanding> get understanding => {
    for (final e in ((_json(_understanding) as Map?) ?? const {}).entries)
      '${e.key}': ?_try(
        () => HabitUnderstanding.fromJson(e.value as Map<String, dynamic>),
      ),
  };

  Future<void> saveUnderstanding(Map<String, HabitUnderstanding> v) => _put(
    _understanding,
    {for (final e in v.entries) e.key: e.value.toJson()},
  );

  LifeContext get life => switch (_json(_life)) {
    final Map<String, dynamic> j => LifeContext.fromJson(j),
    _ => const LifeContext(),
  };

  Future<void> saveLife(LifeContext v) => _put(_life, v.toJson());

  List<HardDay> get hardDays => _list(_hardDays, HardDay.fromJson);

  Future<void> saveHardDays(List<HardDay> v) =>
      _put(_hardDays, [for (final d in v.take(400)) d.toJson()]);

  /// Talks in progress per habit (kept when there's no connection).
  Map<String, List<CoachMessage>> get talks => {
    for (final e in ((_json(_talks) as Map?) ?? const {}).entries)
      '${e.key}': [
        for (final m in (e.value as List))
          CoachMessage.fromJson(m as Map<String, dynamic>),
      ],
  };

  Future<void> saveTalks(Map<String, List<CoachMessage>> v) => _put(_talks, {
    for (final e in v.entries) e.key: [for (final m in e.value) m.toJson()],
  });

  List<HabitTask> get tasks => _list(_tasks, HabitTask.fromJson);

  /// Open tasks, plus done ones from the last 60 days.
  Future<void> saveTasks(List<HabitTask> v) {
    final since = DateTime.now().subtract(const Duration(days: 60));
    return _put(_tasks, [
      for (final t in v)
        if (!t.done || t.doneAt!.isAfter(since)) t.toJson(),
    ]);
  }

  /// Your to-do categories; there's always the default one.
  List<TaskList> get taskLists {
    final lists = _list(_taskLists, TaskList.fromJson);
    if (lists.any((l) => l.id == TaskList.defaultId)) return lists;
    return [
      const TaskList(id: TaskList.defaultId, title: 'My Tasks'),
      ...lists,
    ];
  }

  Future<void> saveTaskLists(List<TaskList> v) =>
      _put(_taskLists, [for (final l in v) l.toJson()]);

  /// The to-do with what's needed to sync it.
  TasksData get tasksData {
    final gone = _json(_tasksGone) as Map? ?? const {};
    final synced = _json(_tasksSynced) as Map? ?? const {};
    return TasksData(
      lists: taskLists,
      tasks: tasks,
      goneTasks: [
        for (final g in (gone['tasks'] as List? ?? const []))
          (gid: g['g'] as String, list: g['l'] as String),
      ],
      goneLists: [for (final g in (gone['lists'] as List? ?? const [])) '$g'],
      syncedAt: {
        for (final e in synced.entries)
          if (DateTime.tryParse('${e.value}') case final DateTime t)
            '${e.key}': t,
      },
    );
  }

  Future<void> saveTasksData(TasksData d) async {
    await saveTasks(d.tasks);
    await saveTaskLists(d.lists);
    await _put(_tasksGone, {
      'tasks': [
        for (final g in d.goneTasks) {'g': g.gid, 'l': g.list},
      ],
      'lists': d.goneLists,
    });
    await _put(_tasksSynced, {
      for (final e in d.syncedAt.entries) e.key: e.value.toIso8601String(),
    });
  }

  /// Forgets the Google side (after disconnecting): tasks stay, as local.
  Future<void> forgetTasksSync() async {
    await saveTasksData(
      TasksData(
        lists: [for (final l in taskLists) TaskList(id: l.id, title: l.title)],
        tasks: [
          for (final t in tasks)
            HabitTask(
              id: t.id,
              title: t.title,
              note: t.note,
              due: t.due,
              doneAt: t.doneAt,
              createdAt: t.createdAt,
              fromSystem: t.fromSystem,
              listId: t.listId,
              updatedAt: t.updatedAt,
            ),
        ],
      ),
    );
  }

  List<AidEntry> get aidKit => _list(_aid, AidEntry.fromJson);

  Future<void> saveAidKit(List<AidEntry> v) =>
      _put(_aid, [for (final e in v) e.toJson()]);

  List<AidUse> get aidUses => _list(_aidUses, AidUse.fromJson);

  Future<void> saveAidUses(List<AidUse> v) =>
      _put(_aidUses, [for (final u in v.take(500)) u.toJson()]);

  /// Day snapshots, newest first.
  List<DaySnapshot> get days =>
      _list(_days, DaySnapshot.fromJson)
        ..sort((a, b) => b.day.compareTo(a.day));

  Future<void> saveDays(List<DaySnapshot> v) {
    final sorted = [...v]..sort((a, b) => b.day.compareTo(a.day));
    return _put(_days, [for (final d in sorted.take(120)) d.toJson()]);
  }

  List<WeeklyReview> get reviews =>
      _list(_reviews, WeeklyReview.fromJson)
        ..sort((a, b) => b.date.compareTo(a.date));

  Future<void> saveReviews(List<WeeklyReview> v) =>
      _put(_reviews, [for (final r in v.take(20)) r.toJson()]);

  /// Small one-off flags (dismissed fresh starts…).
  Map<String, String> get flags => {
    for (final e in ((_json(_flags) as Map?) ?? const {}).entries)
      '${e.key}': '${e.value}',
  };

  Future<void> saveFlags(Map<String, String> v) => _put(_flags, v);
}
