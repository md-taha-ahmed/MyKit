import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/entities/fitness_entities.dart';

/// Plan, workouts, body log, profile and the user's own exercises/photos,
/// as JSON in shared preferences (small and local, like the other tools).
class FitnessStore {
  FitnessStore(this._prefs);

  final SharedPreferences _prefs;

  static const _routinesKey = 'fitness.routines.v1';
  static const _sessionsKey = 'fitness.sessions.v1';
  static const _bodyKey = 'fitness.body.v1';
  static const _profileKey = 'fitness.profile.v1';
  static const _customExercisesKey = 'fitness.customExercises.v1';
  static const _customImagesKey = 'fitness.customImages.v1';
  static const _draftKey = 'fitness.draft.v1';

  List<Map<String, dynamic>> _list(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _putList(String key, Iterable<Object?> items) =>
      _prefs.setString(key, jsonEncode(items.toList()));

  /// Null until the plan has been set up (first launch).
  List<Routine>? readRoutines() => _prefs.containsKey(_routinesKey)
      ? _list(_routinesKey).map(Routine.fromJson).toList()
      : null;

  Future<void> writeRoutines(List<Routine> v) =>
      _putList(_routinesKey, v.map((r) => r.toJson()));

  List<WorkoutSession> readSessions() =>
      _list(_sessionsKey).map(WorkoutSession.fromJson).toList();

  Future<void> writeSessions(List<WorkoutSession> v) =>
      _putList(_sessionsKey, v.map((s) => s.toJson()));

  List<BodyEntry> readBody() =>
      _list(_bodyKey).map(BodyEntry.fromJson).toList();

  Future<void> writeBody(List<BodyEntry> v) =>
      _putList(_bodyKey, v.map((b) => b.toJson()));

  FitnessProfile readProfile() {
    final raw = _prefs.getString(_profileKey);
    if (raw == null) return const FitnessProfile();
    try {
      return FitnessProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const FitnessProfile();
    }
  }

  Future<void> writeProfile(FitnessProfile p) =>
      _prefs.setString(_profileKey, jsonEncode(p.toJson()));

  List<Exercise> readCustomExercises() =>
      _list(_customExercisesKey).map(Exercise.fromJson).toList();

  Future<void> writeCustomExercises(List<Exercise> v) =>
      _putList(_customExercisesKey, v.map((e) => e.toJson()));

  /// exerciseId → local photo paths added by the user.
  Map<String, List<String>> readCustomImages() {
    final raw = _prefs.getString(_customImagesKey);
    if (raw == null) return const {};
    try {
      return {
        for (final e in (jsonDecode(raw) as Map<String, dynamic>).entries)
          e.key: [...(e.value as List).cast<String>()],
      };
    } catch (_) {
      return const {};
    }
  }

  Future<void> writeCustomImages(Map<String, List<String>> v) =>
      _prefs.setString(_customImagesKey, jsonEncode(v));

  /// The workout in progress, so it survives leaving the screen or the app.
  Map<String, dynamic>? readDraft() {
    final raw = _prefs.getString(_draftKey);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeDraft(Map<String, dynamic>? draft) => draft == null
      ? _prefs.remove(_draftKey)
      : _prefs.setString(_draftKey, jsonEncode(draft));
}
