import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../../core/i18n/i18n.dart';
import '../../../../core/storage/app_directories.dart';
import '../../../../core/storage/shared_preferences_provider.dart';
import '../../data/exercise_library_source.dart';
import '../../data/fitness_notifications.dart';
import '../../data/fitness_store.dart';
import '../../domain/default_plan.dart';
import '../../domain/entities/fitness_entities.dart';

const fitnessAccent = Color(0xFF34C759);

// ---------------------------------------------------------------------------
// Dependencies
// ---------------------------------------------------------------------------

final fitnessStoreProvider = Provider<FitnessStore>(
  (ref) => FitnessStore(ref.watch(sharedPreferencesProvider)),
);

final exerciseLibrarySourceProvider = Provider<ExerciseLibrarySource>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return ExerciseLibrarySource(
    client,
    ref.watch(appDocumentsDirectoryProvider),
  );
});

final fitnessNotificationsProvider = Provider<FitnessNotifications>(
  (ref) => FitnessNotifications(),
);

// ---------------------------------------------------------------------------
// Exercise library
// ---------------------------------------------------------------------------

/// Database exercises plus the user's own, by id.
final exerciseLibraryProvider = FutureProvider<Map<String, Exercise>>((
  ref,
) async {
  final db = await ref.read(exerciseLibrarySourceProvider).load();
  final custom = ref.watch(customExercisesProvider);
  return {for (final e in db) e.id: e, for (final e in custom) e.id: e};
});

final exerciseProvider = Provider.family<Exercise?, String>(
  (ref, id) => ref.watch(exerciseLibraryProvider).value?[id],
);

final customExercisesProvider =
    NotifierProvider<CustomExercisesNotifier, List<Exercise>>(
      CustomExercisesNotifier.new,
    );

class CustomExercisesNotifier extends Notifier<List<Exercise>> {
  FitnessStore get _store => ref.read(fitnessStoreProvider);

  @override
  List<Exercise> build() => _store.readCustomExercises();

  Future<Exercise> add({
    required String name,
    required String? equipment,
    required List<String> primary,
    List<String> secondary = const [],
    List<String> instructions = const [],
  }) async {
    final e = Exercise(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim(),
      equipment: equipment,
      primaryMuscles: primary,
      secondaryMuscles: secondary,
      instructions: instructions,
      custom: true,
    );
    state = [...state, e];
    await _store.writeCustomExercises(state);
    return e;
  }

  Future<void> remove(String id) async {
    state = state.where((e) => e.id != id).toList();
    await _store.writeCustomExercises(state);
  }
}

/// The user's own photos per exercise (shown before the database ones).
final customImagesProvider =
    NotifierProvider<CustomImagesNotifier, Map<String, List<String>>>(
      CustomImagesNotifier.new,
    );

class CustomImagesNotifier extends Notifier<Map<String, List<String>>> {
  FitnessStore get _store => ref.read(fitnessStoreProvider);

  @override
  Map<String, List<String>> build() => _store.readCustomImages();

  Future<void> add(String exerciseId, String pickedPath) async {
    final saved = await ref
        .read(exerciseLibrarySourceProvider)
        .saveCustomImage(exerciseId, pickedPath);
    state = {
      ...state,
      exerciseId: [...?state[exerciseId], saved],
    };
    await _store.writeCustomImages(state);
  }

  Future<void> remove(String exerciseId, String path) async {
    await ref.read(exerciseLibrarySourceProvider).deleteFile(path);
    final rest = [...?state[exerciseId]]..remove(path);
    state = {...state, exerciseId: rest}..removeWhere((_, v) => v.isEmpty);
    await _store.writeCustomImages(state);
  }
}

/// A database photo as a local file (downloaded once, then cached).
final exerciseImageFileProvider = FutureProvider.autoDispose
    .family<File, String>((ref, path) async {
      final file = await ref.read(exerciseLibrarySourceProvider).image(path);
      ref.keepAlive();
      return file;
    });

// ---------------------------------------------------------------------------
// Plan
// ---------------------------------------------------------------------------

final routinesProvider = NotifierProvider<RoutinesNotifier, List<Routine>>(
  RoutinesNotifier.new,
);

class RoutinesNotifier extends Notifier<List<Routine>> {
  FitnessStore get _store => ref.read(fitnessStoreProvider);

  @override
  List<Routine> build() => _store.readRoutines() ?? defaultPlan();

  Future<void> _save(List<Routine> v) async {
    state = v;
    await _store.writeRoutines(v);
    await ref.read(fitnessProfileProvider.notifier).syncReminders();
  }

  Routine? byId(String id) => state.where((r) => r.id == id).firstOrNull;

  Future<void> update(Routine r) =>
      _save([for (final x in state) x.id == r.id ? r : x]);

  Future<Routine> add(String name) async {
    final r = Routine(
      id: 'routine_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim().isEmpty ? tr('Workout') : name.trim(),
    );
    await _save([...state, r]);
    return r;
  }

  Future<void> remove(String id) =>
      _save(state.where((r) => r.id != id).toList());

  Future<void> resetToDefault() => _save(defaultPlan());
}

/// Today's routine, or else the next scheduled one (with its weekday).
final nextRoutineProvider = Provider<({Routine routine, int inDays})?>((ref) {
  final routines = ref.watch(routinesProvider);
  final today = DateTime.now().weekday;
  for (var i = 0; i < 7; i++) {
    final day = (today - 1 + i) % 7 + 1;
    final r = routines.where((r) => r.weekdays.contains(day)).firstOrNull;
    if (r != null) return (routine: r, inDays: i);
  }
  return null;
});

// ---------------------------------------------------------------------------
// History, body log, profile
// ---------------------------------------------------------------------------

/// Finished workouts, newest first.
final sessionsProvider =
    NotifierProvider<SessionsNotifier, List<WorkoutSession>>(
      SessionsNotifier.new,
    );

class SessionsNotifier extends Notifier<List<WorkoutSession>> {
  FitnessStore get _store => ref.read(fitnessStoreProvider);

  @override
  List<WorkoutSession> build() =>
      _store.readSessions()..sort((a, b) => b.startedAt.compareTo(a.startedAt));

  Future<void> add(WorkoutSession s) async {
    state = [s, ...state];
    await _store.writeSessions(state);
  }

  Future<void> remove(String id) async {
    state = state.where((s) => s.id != id).toList();
    await _store.writeSessions(state);
  }
}

/// Body weight / measurements, oldest first, one entry per day.
final bodyLogProvider = NotifierProvider<BodyLogNotifier, List<BodyEntry>>(
  BodyLogNotifier.new,
);

class BodyLogNotifier extends Notifier<List<BodyEntry>> {
  FitnessStore get _store => ref.read(fitnessStoreProvider);

  @override
  List<BodyEntry> build() =>
      _store.readBody()..sort((a, b) => a.date.compareTo(b.date));

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Adds or replaces the entry for that day (merging measurements).
  Future<void> save(BodyEntry e) async {
    final old = state.where((x) => _sameDay(x.date, e.date)).firstOrNull;
    final merged = BodyEntry(
      date: e.date,
      weightKg: e.weightKg ?? old?.weightKg,
      waistCm: e.waistCm ?? old?.waistCm,
      chestCm: e.chestCm ?? old?.chestCm,
      armCm: e.armCm ?? old?.armCm,
      hipsCm: e.hipsCm ?? old?.hipsCm,
      thighCm: e.thighCm ?? old?.thighCm,
    );
    state = [
      for (final x in state)
        if (!_sameDay(x.date, e.date)) x,
      merged,
    ]..sort((a, b) => a.date.compareTo(b.date));
    await _store.writeBody(state);
  }

  Future<void> remove(DateTime date) async {
    state = state.where((x) => !_sameDay(x.date, date)).toList();
    await _store.writeBody(state);
  }

  double? get latestWeight =>
      state.lastWhere((e) => e.weightKg != null, orElse: _none).weightKg;

  static BodyEntry _none() => BodyEntry(date: DateTime(0));
}

final fitnessProfileProvider =
    NotifierProvider<FitnessProfileNotifier, FitnessProfile>(
      FitnessProfileNotifier.new,
    );

class FitnessProfileNotifier extends Notifier<FitnessProfile> {
  FitnessStore get _store => ref.read(fitnessStoreProvider);

  @override
  FitnessProfile build() => _store.readProfile();

  Future<void> update(FitnessProfile p) async {
    state = p;
    await _store.writeProfile(p);
    await syncReminders();
  }

  /// Turns reminders on (asking for permission). False if not allowed.
  Future<bool> enableReminders(bool on) async {
    if (on &&
        !await ref.read(fitnessNotificationsProvider).requestPermission()) {
      return false;
    }
    await update(state.copyWith(remindersOn: on));
    return true;
  }

  /// Re-schedules reminders for the plan's training days.
  Future<void> syncReminders() async {
    final routines = ref.read(routinesProvider);
    final days = state.remindersOn
        ? {for (final r in routines) ...r.weekdays}
        : <int>{};
    await ref
        .read(fitnessNotificationsProvider)
        .scheduleReminders(
          days,
          state.reminderMinutes,
          bodyFor: (d) {
            final names = [
              for (final r in routines)
                if (r.weekdays.contains(d)) r.name,
            ];
            return names.isEmpty
                ? tr('Time to train.')
                : tr('Today: {names}. Let\'s go!', {
                    'names': names.join(' + '),
                  });
          },
        );
  }
}

// ---------------------------------------------------------------------------
// Workout in progress
// ---------------------------------------------------------------------------

class ActiveSet {
  const ActiveSet({
    this.reps = 0,
    this.weightKg = 0,
    this.seconds = 0,
    this.done = false,
  });

  final int reps;
  final double weightKg;
  final int seconds;
  final bool done;

  ActiveSet copyWith({int? reps, double? weightKg, int? seconds, bool? done}) =>
      ActiveSet(
        reps: reps ?? this.reps,
        weightKg: weightKg ?? this.weightKg,
        seconds: seconds ?? this.seconds,
        done: done ?? this.done,
      );

  Map<String, Object?> toJson() => {
    'reps': reps,
    'kg': weightKg,
    's': seconds,
    'done': done,
  };

  factory ActiveSet.fromJson(Map<String, dynamic> j) => ActiveSet(
    reps: j['reps'] as int? ?? 0,
    weightKg: (j['kg'] as num?)?.toDouble() ?? 0,
    seconds: j['s'] as int? ?? 0,
    done: j['done'] as bool? ?? false,
  );
}

class ActiveExercise {
  const ActiveExercise({required this.item, required this.sets});

  final PlanItem item;
  final List<ActiveSet> sets;

  ActiveExercise withSets(List<ActiveSet> sets) =>
      ActiveExercise(item: item, sets: sets);

  Map<String, Object?> toJson() => {
    'item': item.toJson(),
    'sets': [for (final s in sets) s.toJson()],
  };

  factory ActiveExercise.fromJson(Map<String, dynamic> j) => ActiveExercise(
    item: PlanItem.fromJson(j['item'] as Map<String, dynamic>),
    sets: [
      for (final s in (j['sets'] as List? ?? const []))
        ActiveSet.fromJson(s as Map<String, dynamic>),
    ],
  );
}

class ActiveWorkout {
  const ActiveWorkout({
    required this.startedAt,
    required this.exercises,
    this.routineId,
    this.routineName,
    this.current = 0,
  });

  final DateTime startedAt;
  final String? routineId;
  final String? routineName;
  final List<ActiveExercise> exercises;
  final int current;

  int get doneSets =>
      exercises.fold(0, (n, e) => n + e.sets.where((s) => s.done).length);

  int get totalSets => exercises.fold(0, (n, e) => n + e.sets.length);

  ActiveWorkout copyWith({List<ActiveExercise>? exercises, int? current}) =>
      ActiveWorkout(
        startedAt: startedAt,
        routineId: routineId,
        routineName: routineName,
        exercises: exercises ?? this.exercises,
        current: current ?? this.current,
      );

  Map<String, dynamic> toJson() => {
    'start': startedAt.toIso8601String(),
    'routineId': routineId,
    'routineName': routineName,
    'current': current,
    'exercises': [for (final e in exercises) e.toJson()],
  };

  factory ActiveWorkout.fromJson(Map<String, dynamic> j) => ActiveWorkout(
    startedAt: DateTime.parse(j['start'] as String),
    routineId: j['routineId'] as String?,
    routineName: j['routineName'] as String?,
    current: j['current'] as int? ?? 0,
    exercises: [
      for (final e in (j['exercises'] as List? ?? const []))
        ActiveExercise.fromJson(e as Map<String, dynamic>),
    ],
  );
}

final activeWorkoutProvider =
    NotifierProvider<ActiveWorkoutNotifier, ActiveWorkout?>(
      ActiveWorkoutNotifier.new,
    );

class ActiveWorkoutNotifier extends Notifier<ActiveWorkout?> {
  FitnessStore get _store => ref.read(fitnessStoreProvider);

  @override
  ActiveWorkout? build() {
    final draft = _store.readDraft();
    if (draft == null) return null;
    try {
      return ActiveWorkout.fromJson(draft);
    } catch (_) {
      return null;
    }
  }

  void _set(ActiveWorkout? w) {
    state = w;
    _store.writeDraft(w?.toJson());
  }

  /// Starts [routine], pre-filling each set from the last time.
  void start(Routine? routine) {
    final sessions = ref.read(sessionsProvider);
    _set(
      ActiveWorkout(
        startedAt: DateTime.now(),
        routineId: routine?.id,
        routineName: routine?.name ?? tr('Free workout'),
        exercises: [
          for (final item in routine?.items ?? const <PlanItem>[])
            _fresh(item, sessions),
        ],
      ),
    );
  }

  ActiveExercise _fresh(PlanItem item, List<WorkoutSession> sessions) {
    List<LoggedSet>? last;
    for (final s in sessions) {
      final log = s.exercises
          .where((e) => e.exerciseId == item.exerciseId)
          .firstOrNull;
      if (log != null && log.sets.isNotEmpty) {
        last = log.sets;
        break;
      }
    }
    return ActiveExercise(
      item: item,
      sets: [
        for (var i = 0; i < item.sets; i++)
          ActiveSet(
            reps: last != null && i < last.length
                ? last[i].reps
                : item.timed
                ? 0
                : item.repsMin,
            weightKg: last != null && i < last.length
                ? last[i].weightKg
                : last?.lastOrNull?.weightKg ?? 0,
            seconds: item.seconds ?? 0,
          ),
      ],
    );
  }

  void goTo(int index) {
    final w = state;
    if (w == null) return;
    _set(w.copyWith(current: index.clamp(0, w.exercises.length - 1)));
  }

  void updateSet(int exercise, int set, ActiveSet value) {
    final w = state;
    if (w == null) return;
    final ex = w.exercises[exercise];
    final sets = [...ex.sets]..[set] = value;
    final list = [...w.exercises]..[exercise] = ex.withSets(sets);
    _set(w.copyWith(exercises: list));
  }

  void addSet(int exercise) {
    final w = state;
    if (w == null) return;
    final ex = w.exercises[exercise];
    final last = ex.sets.lastOrNull ?? const ActiveSet();
    final list = [...w.exercises]
      ..[exercise] = ex.withSets([...ex.sets, last.copyWith(done: false)]);
    _set(w.copyWith(exercises: list));
  }

  void removeSet(int exercise, int set) {
    final w = state;
    if (w == null) return;
    final ex = w.exercises[exercise];
    if (ex.sets.length <= 1) return;
    final list = [...w.exercises]
      ..[exercise] = ex.withSets([...ex.sets]..removeAt(set));
    _set(w.copyWith(exercises: list));
  }

  void addExercise(String exerciseId) {
    final w = state;
    if (w == null) return;
    final ex = _fresh(
      PlanItem(exerciseId: exerciseId),
      ref.read(sessionsProvider),
    );
    _set(
      w.copyWith(exercises: [...w.exercises, ex], current: w.exercises.length),
    );
  }

  /// Saves the done sets as a session. Returns it (null if nothing done).
  Future<WorkoutSession?> finish() async {
    final w = state;
    if (w == null) return null;
    final logs = [
      for (final e in w.exercises)
        if (e.sets.any((s) => s.done))
          ExerciseLog(
            exerciseId: e.item.exerciseId,
            sets: [
              for (final s in e.sets)
                if (s.done)
                  LoggedSet(
                    reps: s.reps,
                    weightKg: s.weightKg,
                    seconds: e.item.timed ? s.seconds : 0,
                  ),
            ],
          ),
    ];
    _set(null);
    await ref.read(fitnessNotificationsProvider).cancelRest();
    if (logs.isEmpty) return null;
    final session = WorkoutSession(
      id: 'w_${w.startedAt.millisecondsSinceEpoch}',
      startedAt: w.startedAt,
      finishedAt: DateTime.now(),
      routineId: w.routineId,
      routineName: w.routineName,
      exercises: logs,
    );
    await ref.read(sessionsProvider.notifier).add(session);
    return session;
  }

  Future<void> discard() async {
    _set(null);
    await ref.read(fitnessNotificationsProvider).cancelRest();
  }
}
