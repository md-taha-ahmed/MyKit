import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/ai/gemini_client.dart';
import '../../../../core/i18n/i18n.dart';
import '../../../../core/storage/shared_preferences_provider.dart';
import '../../../fitness/domain/entities/fitness_entities.dart';
import '../../../fitness/presentation/providers/fitness_providers.dart';
import '../../../fitness/presentation/widgets/exercise_options.dart';
import '../../data/habit_coach.dart';
import '../../data/habit_notifications.dart';
import '../../data/habit_store.dart';
import '../../domain/habit_analysis.dart';
import '../../domain/habit_models.dart';

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
  });

  final List<Habit> habits;
  final List<CheckIn> checks;
  final List<AutomaticityCheck> weekly;
  final List<CoachNote> notes;
  final Map<String, HabitUnderstanding> understanding;
  final LifeContext life;
  final List<HardDay> hardDays;
  final Map<String, List<CoachMessage>> talks;

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
  }) => HabitsState(
    habits: habits ?? this.habits,
    checks: checks ?? this.checks,
    weekly: weekly ?? this.weekly,
    notes: notes ?? this.notes,
    understanding: understanding ?? this.understanding,
    life: life ?? this.life,
    hardDays: hardDays ?? this.hardDays,
    talks: talks ?? this.talks,
  );
}

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
    );
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
  }

  Future<void> clearCheck(String habitId, String day) async {
    final checks = state.checks
        .where((x) => !(x.habitId == habitId && x.day == day))
        .toList();
    state = state.copyWith(checks: checks);
    await _store.saveCheckIns(checks);
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
    final habit = state.habit(habitId)!;
    final talk = state.talks[habitId] ?? const <CoachMessage>[];
    final coach = HabitCoach(ref.read(geminiClientProvider));
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
    if (habit == null) return;
    final described = <String>[];
    for (final c in accepted) {
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
      }
    }
    await save(habit!);
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
