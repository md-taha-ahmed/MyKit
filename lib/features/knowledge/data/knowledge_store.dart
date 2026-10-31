import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/knowledge_models.dart';

/// Everything the Knowledge tool keeps, in SharedPreferences (so the Drive
/// backup includes it): settings, reading positions, past and saved lessons,
/// AI explanations and followed sources.
class KnowledgeStore {
  KnowledgeStore(this._prefs);

  final SharedPreferences _prefs;

  static const _settingsKey = 'knowledge.settings.v1';
  static const _positionsKey = 'knowledge.positions.v1';
  static const _historyKey = 'knowledge.history.v1';
  static const _savedKey = 'knowledge.saved.v1';
  static const _lastReadKey = 'knowledge.lastRead.v1';
  static const _explanationsKey = 'knowledge.explanations.v1';
  static const _onThisDayKey = 'knowledge.onThisDay.v1';
  static const _sourcesKey = 'knowledge.sources.v1';
  static const _itemsKey = 'knowledge.sourceItems.v1';
  static const _lastCheckKey = 'knowledge.sourcesCheckedAt';

  static const _historyLimit = 400;
  static const _explanationsLimit = 150;

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

  List<Lesson> _lessons(String key) => [
    for (final j in (_json(key) as List?) ?? const []) ?_tryLesson(j),
  ];

  static Lesson? _tryLesson(Object? j) {
    try {
      return Lesson.fromJson(j as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  // Settings -------------------------------------------------------------------

  KnowledgeSettings get settings => switch (_json(_settingsKey)) {
    final Map<String, dynamic> j => KnowledgeSettings.fromJson(j),
    _ => const KnowledgeSettings(),
  };

  Future<void> saveSettings(KnowledgeSettings s) =>
      _put(_settingsKey, s.toJson());

  // Positions ------------------------------------------------------------------

  Map<String, TrackPosition> get positions => {
    for (final e in ((_json(_positionsKey) as Map?) ?? const {}).entries)
      '${e.key}': TrackPosition.fromJson(e.value as Map<String, dynamic>),
  };

  Future<void> savePositions(Map<String, TrackPosition> p) =>
      _put(_positionsKey, {for (final e in p.entries) e.key: e.value.toJson()});

  // Lessons --------------------------------------------------------------------

  /// Daily lessons, newest first.
  List<Lesson> get history => _lessons(_historyKey);

  Future<void> saveHistory(List<Lesson> lessons) => _put(_historyKey, [
    for (final l in lessons.take(_historyLimit)) l.toJson(),
  ]);

  List<Lesson> get saved => _lessons(_savedKey);

  Future<void> saveSaved(List<Lesson> lessons) =>
      _put(_savedKey, [for (final l in lessons) l.toJson()]);

  /// The passage last read per track (where the reader reopens).
  Map<String, Lesson> get lastRead => {
    for (final e in ((_json(_lastReadKey) as Map?) ?? const {}).entries)
      '${e.key}': ?_tryLesson(e.value),
  };

  Future<void> saveLastRead(Map<String, Lesson> m) =>
      _put(_lastReadKey, {for (final e in m.entries) e.key: e.value.toJson()});

  Lesson? get onThisDay => _tryLesson(_json(_onThisDayKey));

  Future<void> saveOnThisDay(Lesson l) => _put(_onThisDayKey, l.toJson());

  // AI explanations ------------------------------------------------------------

  String? explanation(String lessonId) =>
      ((_json(_explanationsKey) as Map?) ?? const {})[lessonId] as String?;

  Future<void> saveExplanation(String lessonId, String text) {
    final map = Map<String, dynamic>.from(
      (_json(_explanationsKey) as Map?) ?? const {},
    )..remove(lessonId);
    map[lessonId] = text;
    while (map.length > _explanationsLimit) {
      map.remove(map.keys.first);
    }
    return _put(_explanationsKey, map);
  }

  // Sources --------------------------------------------------------------------

  List<KnowledgeSource> get sources => [
    for (final j in (_json(_sourcesKey) as List?) ?? const [])
      KnowledgeSource.fromJson(j as Map<String, dynamic>),
  ];

  Future<void> saveSources(List<KnowledgeSource> s) =>
      _put(_sourcesKey, [for (final x in s) x.toJson()]);

  List<SourceItem> get items => [
    for (final j in (_json(_itemsKey) as List?) ?? const [])
      SourceItem.fromJson(j as Map<String, dynamic>),
  ];

  Future<void> saveItems(List<SourceItem> items) =>
      _put(_itemsKey, [for (final i in items) i.toJson()]);

  /// When the sites were last checked (by the app or in the background).
  DateTime? get lastSourceCheck => switch (_prefs.getInt(_lastCheckKey)) {
    final ms? => DateTime.fromMillisecondsSinceEpoch(ms),
    null => null,
  };

  Future<void> saveLastSourceCheck(DateTime at) =>
      _prefs.setInt(_lastCheckKey, at.millisecondsSinceEpoch);

  /// Picks up what the background check wrote (another isolate).
  Future<void> reload() => _prefs.reload();
}
