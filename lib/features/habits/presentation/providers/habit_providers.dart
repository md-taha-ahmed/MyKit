import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/ai/gemini_client.dart';
import '../../../../core/i18n/i18n.dart';
import '../../../../core/storage/shared_preferences_provider.dart';
import '../../../fitness/domain/entities/fitness_entities.dart';
import '../../../fitness/presentation/providers/fitness_providers.dart';
import '../../../fitness/presentation/widgets/exercise_options.dart';
import '../../../fitness/presentation/providers/food_providers.dart';
import '../../../limiter/presentation/providers/limiter_providers.dart';
import '../../data/app_signals.dart';
import '../../data/nudges.dart';
import '../../data/habit_coach.dart';
import '../../data/habit_notifications.dart';
import '../../data/habit_store.dart';
import '../../domain/habit_analysis.dart';
import '../../domain/habit_models.dart';
import '../../domain/patterns.dart';

/// Solo Leveling "System" blue.
const habitsAccent = Color(0xFF4FC3F7);

final habitStoreProvider = Provider<HabitStore>(
  (ref) => HabitStore(ref.watch(sharedPreferencesProvider)),
);

final habitNotificationsProvider = Provider<HabitNotifications>(
  (ref) => HabitNotifications(),
);

class HabitsState {
  const HabitsState({
    this.habits = const [],
    this.checks = const [],
    this.weekly = const [],
    this.notes = const [],
    this.understanding = const {},
    this.life = const LifeContext(),
    this.hardDays = const [],
    this.talks = const {},
    this.tasks = const [],
    this.aidKit = const [],
    this.aidUses = const [],
    this.days = const [],
    this.reviews = const [],
    this.flags = const {},
  });

  final List<Habit> habits;
  final List<CheckIn> checks;
  final List<AutomaticityCheck> weekly;
  final List<CoachNote> notes;
  final Map<String, HabitUnderstanding> understanding;
  final LifeContext life;
  final List<HardDay> hardDays;
  final Map<String, List<CoachMessage>> talks;
  final List<HabitTask> tasks;
  final List<AidEntry> aidKit;
  final List<AidUse> aidUses;

  /// Day snapshots across the app, newest first.
  final List<DaySnapshot> days;
  final List<WeeklyReview> reviews;
  final Map<String, String> flags;

  List<DayPattern> get patterns => DayPatterns.find(days);

  /// A week since the last review, and a week of data.
  bool get reviewDue =>
      days.length >= 5 &&
      (reviews.isEmpty ||
          DateTime.now().difference(reviews.first.date).inDays >= 7);

  List<HabitTask> get openTasks =>
      tasks.where((t) => !t.done).toList()..sort(_byDue);

  static int _byDue(HabitTask a, HabitTask b) {
    if (a.due == b.due) return a.createdAt.compareTo(b.createdAt);
    if (a.due == null) return 1;
    if (b.due == null) return -1;
    return a.due!.compareTo(b.due!);
  }

  /// How often an aid-kit action helped: (helped, rated).
  ({int helped, int rated}) aidScore(String actionId) {
    var helped = 0, rated = 0;
    for (final u in aidUses) {
      if (u.actionId != actionId || u.helped == null) continue;
      rated++;
      if (u.helped!) helped++;
    }
    return (helped: helped, rated: rated);
  }

  List<Habit> get active => habits.where((h) => !h.archived).toList();

  Habit? habit(String id) => habits.where((h) => h.id == id).firstOrNull;

  Map<String, CheckIn> checksOf(String habitId) => {
    for (final c in checks)
      if (c.habitId == habitId) c.day: c,
  };

  List<AutomaticityCheck> weeklyOf(String habitId) =>
      weekly.where((w) => w.habitId == habitId).toList()
        ..sort((a, b) => a.date.compareTo(b.date));

  List<CoachNote> notesOf(String habitId) =>
      notes.where((n) => n.habitId == habitId).toList()
        ..sort((a, b) => b.date.compareTo(a.date));

  Set<String> get hardDayKeys => {for (final d in hardDays) d.day};

  HardDay? hardDay(String day) =>
      hardDays.where((d) => d.day == day).firstOrNull;

  int get xp => HabitAnalysis.totalXp(checks, weekly, hardDayKeys);

  /// The weekly check is due (a week since the last, or since starting).
  bool weeklyDue(Habit h, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final last = weeklyOf(h.id).lastOrNull?.date ?? h.createdAt;
    return today.difference(last).inDays >= 7;
  }

  HabitsState copyWith({
    List<Habit>? habits,
    List<CheckIn>? checks,
    List<AutomaticityCheck>? weekly,
    List<CoachNote>? notes,
    Map<String, HabitUnderstanding>? understanding,
    LifeContext? life,
    List<HardDay>? hardDays,
    Map<String, List<CoachMessage>>? talks,
    List<HabitTask>? tasks,
    List<AidEntry>? aidKit,
    List<AidUse>? aidUses,
    List<DaySnapshot>? days,
    List<WeeklyReview>? reviews,
    Map<String, String>? flags,
  }) => HabitsState(
    habits: habits ?? this.habits,
    checks: checks ?? this.checks,
    weekly: weekly ?? this.weekly,
    notes: notes ?? this.notes,
    understanding: understanding ?? this.understanding,
    life: life ?? this.life,
    hardDays: hardDays ?? this.hardDays,
    talks: talks ?? this.talks,
    tasks: tasks ?? this.tasks,
    aidKit: aidKit ?? this.aidKit,
    aidUses: aidUses ?? this.aidUses,
    days: days ?? this.days,
    reviews: reviews ?? this.reviews,
    flags: flags ?? this.flags,
  );
}

/// The id of whole-day talks (not about one quest).
const dayTalkId = '_day';

final habitsProvider = NotifierProvider<HabitsNotifier, HabitsState>(
  HabitsNotifier.new,
);

class HabitsNotifier extends Notifier<HabitsState> {
  HabitStore get _store => ref.read(habitStoreProvider);

  @override
  HabitsState build() {
    final s = _store;
    // A finished workout completes workout habits by itself.
    ref.listen(sessionsProvider, (_, sessions) => _syncWorkouts(sessions));
    Future.microtask(() {
      _syncWorkouts(ref.read(sessionsProvider));
      _schedule();
      Nudges.sync(enabled: Nudges.enabled(ref.read(sharedPreferencesProvider)));
      _syncLocks();
      recordDays();
    });
    return HabitsState(
      habits: s.habits,
      checks: s.checkIns,
      weekly: s.weekly,
      notes: s.notes,
      understanding: s.understanding,
      life: s.life,
      hardDays: s.hardDays,
      talks: s.talks,
      tasks: s.tasks,
      aidKit: s.aidKit,
      aidUses: s.aidUses,
      days: s.days,
      reviews: s.reviews,
      flags: s.flags,
    );
  }

  // Day snapshots (v2) -------------------------------------------------------

  /// Records today and the last two weeks from every tool, with Screen time
  /// minutes, so patterns have data even before you open the System.
  Future<void> recordDays() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final now = DateTime.now();
    Map<String, int> social = const {};
    try {
      final status = await ref.read(limiterNativeProvider).status();
      final groups = ref.read(limiterSettingsProvider).groups;
      social = {
        for (final e in status.usage.entries)
          e.key: groups.fold(0, (s, g) => s + (e.value[g.id] ?? 0)) ~/ 60,
      };
    } catch (_) {}
    final target = ref.read(calorieTargetProvider).target;
    final byDay = {for (final d in state.days) d.day: d};
    final moods = <String, List<int>>{};
    for (final c in state.checks) {
      if (c.mood != null) moods.putIfAbsent(c.day, () => []).add(c.mood!);
    }
    for (var i = 0; i < 14; i++) {
      final date = now.subtract(Duration(days: i));
      final s = AppSignals.read(prefs, now: date);
      final m = moods[s.day];
      byDay[s.day] = DaySnapshot(
        day: s.day,
        socialMinutes: social[s.day] ?? byDay[s.day]?.socialMinutes,
        kcal: s.kcal,
        // Only today's target is known for sure.
        kcalTarget: i == 0 ? target : byDay[s.day]?.kcalTarget ?? target,
        meals: s.meals.length,
        lessonRead: s.lessonRead,
        workoutPlanned: s.workoutPlanned != null,
        workoutDone: s.workoutDone,
        questsDue: s.questsDue,
        questsDone: state.checks
            .where((c) => c.day == s.day && c.done)
            .length
            .clamp(0, s.questsDue),
        mood: m == null || m.isEmpty
            ? null
            : m.reduce((a, b) => a + b) / m.length,
        hard: state.hardDayKeys.contains(s.day),
      );
    }
    final days = byDay.values.toList()..sort((a, b) => b.day.compareTo(a.day));
    state = state.copyWith(days: days);
    await _store.saveDays(days);
  }

  /// Today's signals that look off compared to your usual.
  List<String> todayFlags() {
    final today = state.days.where((d) => d.day == habitDay(DateTime.now()));
    if (today.isEmpty) return const [];
    final d = today.first;
    final usual = DayPatterns.usualSocial(state.days.skip(1).toList());
    return [
      if (usual != null && DayPatterns.heavy(d, usual))
        tr('{n} min of social media ({x}× your usual)', {
          'n': d.socialMinutes,
          'x': (d.socialMinutes! / usual).toStringAsFixed(1),
        }),
      if (d.kcalTarget != null && d.kcal > d.kcalTarget! * 1.15)
        tr('Ate {n} kcal over your target', {'n': d.kcal - d.kcalTarget!}),
      if (d.workoutPlanned && !d.workoutDone && DateTime.now().hour >= 20)
        tr('Workout not done'),
      if (d.mood != null && d.mood! <= 2) tr('Low mood'),
    ];
  }

  // Flags --------------------------------------------------------------------

  Future<void> setFlag(String key, String value) async {
    final flags = {...state.flags, key: value};
    state = state.copyWith(flags: flags);
    await _store.saveFlags(flags);
  }

  // Weekly review (v3) -------------------------------------------------------

  Future<WeeklyReview> weeklyReview() async {
    await recordDays();
    final coach = HabitCoach(ref.read(geminiClientProvider));
    final r = await coach.weeklyReview(
      context: _weekContext(),
      arabic: I18n.isArabic,
    );
    final reviews = [r, ...state.reviews];
    state = state.copyWith(reviews: reviews);
    await _store.saveReviews(reviews);
    return r;
  }

  String _weekContext() {
    final b = StringBuffer()
      ..writeln(
        'LIFE CONTEXT: ${state.life.summary.isEmpty ? '(not told)' : state.life.summary}',
      )
      ..writeln('LAST 7 DAYS ACROSS THE APP (newest first):');
    final usual = DayPatterns.usualSocial(state.days);
    for (final d in state.days.take(7)) {
      b.writeln(
        '  ${d.day}: social ${d.socialMinutes ?? '?'} min'
        '${usual == null ? '' : ' (usual $usual)'}, food ${d.kcal}'
        '${d.kcalTarget == null ? '' : '/${d.kcalTarget}'} kcal (${d.meals} meals), '
        'workout ${d.workoutPlanned ? (d.workoutDone ? 'done' : 'skipped') : 'rest'}, '
        'lesson ${d.lessonRead ? 'read' : 'no'}, quests ${d.questsDone}/${d.questsDue}'
        '${d.mood == null ? '' : ', mood ${d.mood!.toStringAsFixed(1)}'}'
        '${d.hard ? ', HARD DAY' : ''}',
      );
    }
    final since = habitDay(DateTime.now().subtract(const Duration(days: 7)));
    for (final h in state.active) {
      final week = state.checks.where(
        (c) => c.habitId == h.id && c.day.compareTo(since) > 0,
      );
      final reasons = HabitAnalysis.reasons(week);
      final u = state.understanding[h.id];
      b.writeln(
        'QUEST ${h.name}: ${week.where((c) => c.done).length} done, '
        '${week.where((c) => c.status == CheckStatus.missed).length} missed'
        '${reasons.isEmpty ? '' : ' (${reasons.map((r) => '${r.$1.name}×${r.$2}').join(', ')})'}'
        '${u == null || u.rootCause.isEmpty ? '' : '; understood: ${u.rootCause}'}',
      );
    }
    for (final p in state.patterns) {
      b.writeln(
        'PATTERN: ${p.text}: ${(p.onHeavy * 100).round()}% on heavy-scrolling days vs ${(p.onNormal * 100).round()}% otherwise (${p.heavyDays}/${p.normalDays} days)',
      );
    }
    final aid = state.aidUses.where(
      (u) => DateTime.now().difference(u.at).inDays < 7,
    );
    if (aid.isNotEmpty) {
      b.writeln(
        'AID KIT USED ${aid.length}× this week (${aid.where((u) => u.helped == true).length} helped)',
      );
    }
    final day = state.understanding[dayTalkId];
    if (day != null && day.rootCause.isNotEmpty) {
      b.writeln('DOWN-DAY PATTERN: ${day.rootCause}; helps: ${day.helps}');
    }
    return b.toString();
  }

  // Quest locks (v3) ---------------------------------------------------------

  /// Tells Screen time which apps stay blocked until a quest is done today.
  Future<void> _syncLocks() async {
    final locked = state.active.where((h) => h.lockGroups.isNotEmpty);
    final now = DateTime.now();
    final recent = {
      for (var i = 0; i < 2; i++) habitDay(now.subtract(Duration(days: i))),
    };
    final locks = [
      for (final h in locked)
        {
          'name': h.name,
          'groups': h.lockGroups,
          'weekdays': h.weekdays.toList(),
          'done': [
            for (final d in recent)
              if (_cleared(h.id, d)) d,
          ],
        },
    ];
    try {
      await ref.read(limiterNativeProvider).setQuestLocks(jsonEncode(locks));
    } catch (_) {}
  }

  /// Done, excused or a hard day: the lock is off.
  bool _cleared(String habitId, String day) {
    final c = state.checksOf(habitId)[day];
    return (c != null && (c.done || c.status == CheckStatus.excused)) ||
        state.hardDayKeys.contains(day);
  }

  /// Moves a habit's reminder to when you actually do it.
  Future<void> moveReminder(String habitId, int minutes) async {
    final h = state.habit(habitId);
    if (h != null) await save(h.copyWith(reminderMinutes: minutes));
  }

  // Tasks --------------------------------------------------------------------

  Future<void> _saveTasks(List<HabitTask> tasks) async {
    state = state.copyWith(tasks: tasks);
    await _store.saveTasks(tasks);
  }

  Future<void> addTask(
    String title, {
    String? due,
    String note = '',
    bool fromSystem = false,
  }) => _saveTasks([
    ...state.tasks,
    HabitTask(
      id: newId(),
      title: title.trim(),
      note: note,
      due: due,
      createdAt: DateTime.now(),
      fromSystem: fromSystem,
    ),
  ]);

  Future<void> updateTask(HabitTask t) =>
      _saveTasks([for (final x in state.tasks) x.id == t.id ? t : x]);

  Future<void> toggleTask(String id) => _saveTasks([
    for (final t in state.tasks)
      if (t.id == id)
        t.done
            ? t.copyWith(clearDone: true)
            : t.copyWith(doneAt: DateTime.now())
      else
        t,
  ]);

  Future<void> deleteTask(String id) =>
      _saveTasks(state.tasks.where((t) => t.id != id).toList());

  // Aid kit ------------------------------------------------------------------

  Future<void> _saveAid(List<AidEntry> kit) async {
    state = state.copyWith(aidKit: kit);
    await _store.saveAidKit(kit);
  }

  Future<AidEntry> addAidEntry(String feeling, String emoji) async {
    final e = AidEntry(id: newId(), feeling: feeling.trim(), emoji: emoji);
    await _saveAid([...state.aidKit, e]);
    return e;
  }

  Future<void> updateAidEntry(AidEntry e) =>
      _saveAid([for (final x in state.aidKit) x.id == e.id ? e : x]);

  Future<void> deleteAidEntry(String id) =>
      _saveAid(state.aidKit.where((e) => e.id != id).toList());

  Future<void> addAidAction(String entryId, String text) async {
    final e = state.aidKit.where((x) => x.id == entryId).firstOrNull;
    if (e == null || text.trim().isEmpty) return;
    await updateAidEntry(
      e.copyWith(actions: [...e.actions, AidAction(newId(), text.trim())]),
    );
  }

  Future<void> removeAidAction(String entryId, String actionId) async {
    final e = state.aidKit.where((x) => x.id == entryId).firstOrNull;
    if (e == null) return;
    await updateAidEntry(
      e.copyWith(actions: e.actions.where((a) => a.id != actionId).toList()),
    );
  }

  /// You did an action; returns its index in the log to rate it later.
  Future<void> useAid(String entryId, String actionId, {bool? helped}) async {
    final uses = [
      AidUse(
        entryId: entryId,
        actionId: actionId,
        at: DateTime.now(),
        helped: helped,
      ),
      ...state.aidUses,
    ];
    state = state.copyWith(aidUses: uses);
    await _store.saveAidUses(uses);
  }

  /// Rates the latest use of [actionId].
  Future<void> rateAid(String actionId, bool helped) async {
    final i = state.aidUses.indexWhere((u) => u.actionId == actionId);
    if (i < 0) return;
    final uses = [...state.aidUses]..[i] = state.aidUses[i].withHelped(helped);
    state = state.copyWith(aidUses: uses);
    await _store.saveAidUses(uses);
  }

  // Habits -------------------------------------------------------------------

  Future<Habit> save(Habit h) async {
    final exists = state.habits.any((x) => x.id == h.id);
    final habits = exists
        ? [for (final x in state.habits) x.id == h.id ? h : x]
        : [...state.habits, h];
    state = state.copyWith(habits: habits);
    await _store.saveHabits(habits);
    await _schedule();
    await _syncLocks();
    return h;
  }

  static String newId() => const Uuid().v4();

  Future<void> archive(String id, {bool archived = true}) async {
    final h = state.habit(id);
    if (h != null) await save(h.copyWith(archived: archived));
  }

  Future<void> delete(String id) async {
    state = state.copyWith(
      habits: state.habits.where((h) => h.id != id).toList(),
      checks: state.checks.where((c) => c.habitId != id).toList(),
      weekly: state.weekly.where((c) => c.habitId != id).toList(),
      notes: state.notes.where((c) => c.habitId != id).toList(),
      understanding: {...state.understanding}..remove(id),
      talks: {...state.talks}..remove(id),
    );
    await _store.saveHabits(state.habits);
    await _store.saveCheckIns(state.checks);
    await _store.saveWeekly(state.weekly);
    await _store.saveNotes(state.notes);
    await _store.saveUnderstanding(state.understanding);
    await _store.saveTalks(state.talks);
    await _schedule();
  }

  // Check-ins ----------------------------------------------------------------

  Future<void> checkIn(
    String habitId,
    String day,
    CheckStatus status, {
    MissReason? reason,
    String note = '',
    int? mood,
  }) async {
    final c = CheckIn(
      habitId: habitId,
      day: day,
      status: status,
      at: DateTime.now(),
      reason: reason,
      note: note,
      mood: mood,
    );
    final checks = [
      ...state.checks.where((x) => !(x.habitId == habitId && x.day == day)),
      c,
    ];
    state = state.copyWith(checks: checks);
    await _store.saveCheckIns(checks);
    await _syncLocks();
  }

  Future<void> clearCheck(String habitId, String day) async {
    final checks = state.checks
        .where((x) => !(x.habitId == habitId && x.day == day))
        .toList();
    state = state.copyWith(checks: checks);
    await _store.saveCheckIns(checks);
    await _syncLocks();
  }

  Future<void> _syncWorkouts(List<WorkoutSession> sessions) async {
    final linked = state.active.where((h) => h.link == 'fitness');
    if (linked.isEmpty) return;
    final days = {for (final s in sessions) habitDay(s.startedAt)};
    var changed = false;
    final checks = [...state.checks];
    for (final h in linked) {
      for (final day in days) {
        if (h.createdAt.isAfter(
          parseHabitDay(day).add(const Duration(days: 1)),
        )) {
          continue;
        }
        final i = checks.indexWhere((c) => c.habitId == h.id && c.day == day);
        if (i >= 0 && checks[i].done) continue;
        final auto = CheckIn(
          habitId: h.id,
          day: day,
          status: CheckStatus.full,
          at: DateTime.now(),
          auto: true,
        );
        if (i >= 0) {
          checks[i] = auto;
        } else {
          checks.add(auto);
        }
        changed = true;
      }
    }
    if (!changed) return;
    state = state.copyWith(checks: checks);
    await _store.saveCheckIns(checks);
  }

  // Hard days ----------------------------------------------------------------

  /// Marks [day] as a hard day for every habit: only tiny versions are asked
  /// for, and unanswered quests are excused.
  Future<void> setHardDay(String day, MissReason? reason) async {
    final days = [
      ...state.hardDays.where((d) => d.day != day),
      if (reason != null) HardDay(day, reason),
    ]..sort((a, b) => b.day.compareTo(a.day));
    state = state.copyWith(hardDays: days);
    await _store.saveHardDays(days);
    await _syncLocks();
  }

  // Weekly check & life context ----------------------------------------------

  Future<void> addWeekly(String habitId, List<int> scores) async {
    final weekly = [
      ...state.weekly,
      AutomaticityCheck(habitId, DateTime.now(), scores),
    ];
    state = state.copyWith(weekly: weekly);
    await _store.saveWeekly(weekly);
  }

  /// Adds what changed in your life (the System folds it in at the next talk).
  Future<void> tellLife(String text) async {
    final t = text.trim();
    final now = DateTime.now();
    final summary = t.isEmpty
        ? state.life.summary
        : [
            if (state.life.summary.isNotEmpty) state.life.summary,
            '[${habitDay(now)}] $t',
          ].join('\n');
    final life = state.life.copyWith(
      summary: summary,
      updatedAt: t.isEmpty ? null : now,
      lastAskedAt: now,
    );
    state = state.copyWith(life: life);
    await _store.saveLife(life);
  }

  /// Your corrections to what the System knows.
  Future<void> editLife(String summary) async {
    final life = state.life.copyWith(
      summary: summary.trim(),
      updatedAt: DateTime.now(),
    );
    state = state.copyWith(life: life);
    await _store.saveLife(life);
  }

  Future<void> editUnderstanding(String habitId, HabitUnderstanding u) async {
    final map = {...state.understanding, habitId: u};
    state = state.copyWith(understanding: map);
    await _store.saveUnderstanding(map);
  }

  /// The life update is asked about once a week.
  bool get lifeQuestionDue {
    final last = state.life.lastAskedAt;
    return state.active.isNotEmpty &&
        (last == null || DateTime.now().difference(last).inDays >= 7);
  }

  // Talking with the System ---------------------------------------------------

  /// Starts a talk (a local first question; no request yet).
  Future<void> openTalk(String habitId, String opening) async {
    final talks = {
      ...state.talks,
      habitId: [CoachMessage(fromUser: false, text: opening)],
    };
    state = state.copyWith(talks: talks);
    await _store.saveTalks(talks);
  }

  Future<void> _setTalk(String habitId, List<CoachMessage> talk) async {
    final talks = {...state.talks, habitId: talk};
    state = state.copyWith(talks: talks);
    await _store.saveTalks(talks);
  }

  Future<void> closeTalk(String habitId) async {
    final talks = {...state.talks}..remove(habitId);
    state = state.copyWith(talks: talks);
    await _store.saveTalks(talks);
  }

  /// Sends your message (saved first, so nothing is lost without a
  /// connection) and returns the System's reply. Throws [AiException] when
  /// it can't reach Gemini; [retry] sends the saved talk again.
  Future<CoachReply> send(String habitId, String text) async {
    final talk = [
      ...state.talks[habitId] ?? const <CoachMessage>[],
      CoachMessage(fromUser: true, text: text),
    ];
    await _setTalk(habitId, talk);
    return _ask(habitId);
  }

  Future<CoachReply> retry(String habitId) => _ask(habitId);

  Future<CoachReply> _ask(String habitId) async {
    final talk = state.talks[habitId] ?? const <CoachMessage>[];
    final coach = HabitCoach(ref.read(geminiClientProvider));
    if (habitId == dayTalkId) {
      await recordDays();
      final reply = await coach.reply(
        context: HabitCoach.dayContext(
          acrossApp: await todayAcrossApp(),
          days: state.days,
          patterns: state.patterns,
          understanding:
              state.understanding[dayTalkId] ?? const HabitUnderstanding(),
          life: state.life,
          notes: state.notesOf(dayTalkId),
          quests: [
            for (final h in state.active)
              (
                name: h.name,
                today: state
                    .checksOf(h.id)[habitDay(DateTime.now())]
                    ?.status
                    .name,
                rootCause: state.understanding[h.id]?.rootCause ?? '',
              ),
          ],
          tasks: state.tasks,
          aidKit: state.aidKit,
          aidScore: state.aidScore,
        ),
        talk: talk,
        arabic: I18n.isArabic,
        aboutDay: true,
      );
      if (reply.text.isNotEmpty) {
        await _setTalk(habitId, [
          ...talk,
          CoachMessage(fromUser: false, text: reply.text),
        ]);
      }
      return reply;
    }
    final habit = state.habit(habitId)!;
    final reply = await coach.reply(
      context: HabitCoach.context(
        habit: habit,
        checks: state.checksOf(habitId).values.toList(),
        understanding:
            state.understanding[habitId] ?? const HabitUnderstanding(),
        life: state.life,
        notes: state.notesOf(habitId),
        hardDays: state.hardDayKeys,
        weekly: state.weeklyOf(habitId),
        workout: habit.link == 'fitness' ? await workoutContext() : null,
        acrossApp: await todayAcrossApp(),
        tasks: state.tasks,
        aidKit: state.aidKit,
        aidScore: state.aidScore,
        dayPattern: state.understanding[dayTalkId],
        dayNotes: state.notesOf(dayTalkId),
      ),
      talk: talk,
      arabic: I18n.isArabic,
    );
    if (reply.text.isNotEmpty) {
      await _setTalk(habitId, [
        ...talk,
        CoachMessage(fromUser: false, text: reply.text),
      ]);
    }
    return reply;
  }

  /// Keeps what the System understood and applies the changes you accepted.
  Future<void> applyProposal(
    String habitId,
    CoachProposal p,
    List<CoachChange> accepted,
  ) async {
    var habit = state.habit(habitId);
    if (habit == null && habitId != dayTalkId) return;
    final described = <String>[];
    for (final c in accepted) {
      if (habit == null && !{'task', 'aid'}.contains(c.type)) continue;
      switch (c.type) {
        case 'tiny' when c.data['text'] is String:
          habit = habit!.copyWith(tiny: c.data['text'] as String);
          described.add('tiny → ${c.data['text']}');
        case 'full' when c.data['text'] is String:
          habit = habit!.copyWith(full: c.data['text'] as String);
          described.add('full → ${c.data['text']}');
        case 'anchor' when c.data['text'] is String:
          habit = habit!.copyWith(anchor: c.data['text'] as String);
          described.add('anchor → ${c.data['text']}');
        case 'time' when c.data['minutes'] is num:
          habit = habit!.copyWith(
            reminderMinutes: (c.data['minutes'] as num).toInt().clamp(0, 1439),
          );
          described.add('time → ${c.data['minutes']}');
        case 'days' when c.data['weekdays'] is List:
          final days = {
            for (final d in c.data['weekdays'] as List)
              if (d is num && d >= 1 && d <= 7) d.toInt(),
          };
          if (days.isNotEmpty) {
            habit = habit!.copyWith(weekdays: days);
            described.add('days → ${(days.toList()..sort()).join(',')}');
          }
        case 'if_then' when c.data['if'] is String && c.data['then'] is String:
          habit = habit!.copyWith(
            obstacles: [
              ...habit.obstacles,
              IfThen(c.data['if'] as String, c.data['then'] as String),
            ],
          );
          described.add('if ${c.data['if']} → ${c.data['then']}');
        case 'swap_exercise':
          final ok = await _swapExercise(c.data);
          if (ok != null) described.add(ok);
        case 'task' when c.data['title'] is String:
          final due = c.data['due'];
          await addTask(
            c.data['title'] as String,
            due: due is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(due)
                ? due
                : null,
            fromSystem: true,
          );
          described.add('task: ${c.data['title']}');
        case 'aid'
            when c.data['feeling'] is String && c.data['action'] is String:
          final feeling = (c.data['feeling'] as String).trim();
          var entry = state.aidKit
              .where((e) => e.feeling.toLowerCase() == feeling.toLowerCase())
              .firstOrNull;
          entry ??= await addAidEntry(feeling, '🩹');
          await addAidAction(entry.id, c.data['action'] as String);
          described.add('aid kit: $feeling → ${c.data['action']}');
      }
    }
    if (habit != null) await save(habit);
    final notes = [
      ...state.notes,
      CoachNote(
        habitId: habitId,
        date: DateTime.now(),
        insight: p.insight,
        changes: described,
      ),
    ];
    final understanding = {...state.understanding, habitId: p.understanding};
    var life = state.life;
    if (p.life != null) {
      life = life.copyWith(summary: p.life, updatedAt: DateTime.now());
    }
    state = state.copyWith(
      notes: notes,
      understanding: understanding,
      life: life,
    );
    await _store.saveNotes(notes);
    await _store.saveUnderstanding(understanding);
    await _store.saveLife(life);
    await closeTalk(habitId);
  }

  /// Swaps an exercise in a workout, only to an alternative it listed.
  Future<String?> _swapExercise(Map<String, dynamic> d) async {
    final routineId = d['routine'], to = d['to'], index = d['index'];
    if (routineId is! String || to is! String || index is! num) return null;
    final ctx = await workoutContext();
    final e = ctx?.exercises.where((e) => e.index == index.toInt()).firstOrNull;
    if (ctx == null ||
        ctx.routineId != routineId ||
        e == null ||
        !e.alternatives.any((a) => a.id == to)) {
      return null;
    }
    await ref
        .read(routinesProvider.notifier)
        .swap(routineId, index.toInt(), to);
    final name = e.alternatives.firstWhere((a) => a.id == to).name;
    return '${ctx.routineName}: ${e.name} → $name';
  }

  /// Today's workout (or the next one) with skipped exercises and
  /// alternatives, for the System.
  Future<WorkoutContext?> workoutContext() async {
    final routines = ref.read(routinesProvider);
    if (routines.isEmpty) return null;
    final today = DateTime.now().weekday;
    final routine =
        routines.where((r) => r.weekdays.contains(today)).firstOrNull ??
        ref.read(nextRoutineProvider)?.routine;
    if (routine == null) return null;
    Map<String, Exercise> library;
    try {
      library = await ref.read(exerciseLibraryProvider.future);
    } catch (_) {
      library = const {};
    }
    final sessions = ref
        .read(sessionsProvider)
        .where((s) => s.routineId == routine.id)
        .take(6)
        .toList();
    return WorkoutContext(
      routineId: routine.id,
      routineName: routine.name,
      exercises: [
        for (final (i, item) in routine.items.indexed)
          (
            index: i,
            id: item.exerciseId,
            name:
                library[item.exerciseId]?.name ??
                item.exerciseId.replaceAll('_', ' '),
            target: item.target,
            sessions: sessions.length,
            skipped: sessions
                .where(
                  (s) => !s.exercises.any(
                    (l) => l.exerciseId == item.exerciseId && l.sets.isNotEmpty,
                  ),
                )
                .length,
            alternatives: [
              for (final id in similarExercises(routine, item, library).take(4))
                (id: id, name: library[id]?.name ?? id.replaceAll('_', ' ')),
            ],
          ),
      ],
    );
  }

  /// Today in the rest of the app, with the calorie target and social-media
  /// minutes compared to your usual.
  Future<String> todayAcrossApp() async {
    final signals = AppSignals.read(ref.read(sharedPreferencesProvider));
    int? minutes, usual;
    try {
      final status = await ref.read(limiterNativeProvider).status();
      final groups = ref.read(limiterSettingsProvider).groups;
      int total(Map<String, int> day) =>
          groups.fold(0, (s, g) => s + (day[g.id] ?? 0)) ~/ 60;
      final now = DateTime.now();
      minutes = total(status.day(now));
      final past = [
        for (var i = 1; i <= 7; i++)
          total(status.day(now.subtract(Duration(days: i)))),
      ].where((m) => m > 0).toList();
      if (past.isNotEmpty) usual = past.reduce((a, b) => a + b) ~/ past.length;
    } catch (_) {}
    return signals.describe(
      kcalTarget: ref.read(calorieTargetProvider).target,
      socialMinutes: minutes,
      socialUsual: usual,
    );
  }

  // Reminders ----------------------------------------------------------------

  Future<void> _schedule() async {
    try {
      await ref.read(habitNotificationsProvider).schedule(state.active);
    } catch (_) {}
  }
}

/// Player level, XP and stats.
final habitPlayerProvider = Provider((ref) {
  final s = ref.watch(habitsProvider);
  final xp = s.xp;
  return (
    xp: xp,
    level: HabitAnalysis.level(xp),
    stats: HabitAnalysis.stats(s.habits, s.checks),
  );
});
