import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class RssLocalDataSource {
  RssLocalDataSource(this._prefs);

  static const _categoriesKey = 'rss.categories.v1';
  static const _feedsKey = 'rss.feeds.v1';
  static const _articlesKey = 'rss.articles.v1';
  static const _readKey = 'rss.read.v1';
  static const _savedKey = 'rss.saved.v1';
  static const _likedKey = 'rss.liked.v1';
  static const _hiddenKey = 'rss.hidden.v1';

  final SharedPreferences _prefs;

  List<Map<String, dynamic>> readCategories() => _readList(_categoriesKey);
  Future<void> writeCategories(List<Map<String, dynamic>> v) =>
      _prefs.setString(_categoriesKey, jsonEncode(v));

  List<Map<String, dynamic>> readFeeds() => _readList(_feedsKey);
  Future<void> writeFeeds(List<Map<String, dynamic>> v) =>
      _prefs.setString(_feedsKey, jsonEncode(v));

  List<Map<String, dynamic>> readArticles() => _readList(_articlesKey);
  Future<void> writeArticles(List<Map<String, dynamic>> v) =>
      _prefs.setString(_articlesKey, jsonEncode(v));

  Set<String> readReadIds() => (_prefs.getStringList(_readKey) ?? []).toSet();
  Future<void> writeReadIds(Set<String> ids) =>
      _prefs.setStringList(_readKey, ids.toList());

  /// Bookmarked articles are stored in full so they survive feed refreshes.
  List<Map<String, dynamic>> readSaved() => _readList(_savedKey);
  Future<void> writeSaved(List<Map<String, dynamic>> v) =>
      _prefs.setString(_savedKey, jsonEncode(v));

  Set<String> readLiked() => (_prefs.getStringList(_likedKey) ?? []).toSet();
  Future<void> writeLiked(Set<String> ids) =>
      _prefs.setStringList(_likedKey, ids.toList());

  Set<String> readHidden() => (_prefs.getStringList(_hiddenKey) ?? []).toSet();
  Future<void> writeHidden(Set<String> ids) =>
      _prefs.setStringList(_hiddenKey, ids.toList());

  List<Map<String, dynamic>> _readList(String key) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }
}
