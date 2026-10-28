import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/stremio_entities.dart';

/// Default add-ons: Cinemeta (catalogs + details), Torrentio (streams),
/// OpenSubtitles v3 (subtitles).
const defaultAddonUrls = [
  'https://v3-cinemeta.strem.io/manifest.json',
  'https://torrentio.strem.fun/manifest.json',
  'https://opensubtitles-v3.strem.io/manifest.json',
];

class MoviesLocalDataSource {
  MoviesLocalDataSource(this._prefs);

  final SharedPreferences _prefs;

  static const _addonsKey = 'movies.addons.v1';
  static const _historyKey = 'movies.history.v1';
  static const _subLangKey = 'movies.subtitleLang';

  List<String> getAddonUrls() =>
      _prefs.getStringList(_addonsKey) ?? defaultAddonUrls;

  Future<void> saveAddonUrls(List<String> urls) =>
      _prefs.setStringList(_addonsKey, urls);

  List<WatchEntry> getHistory() {
    final raw = _prefs.getString(_historyKey);
    if (raw == null) return [];
    try {
      return [
        for (final e in jsonDecode(raw) as List)
          WatchEntry.fromJson(e as Map<String, dynamic>),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> saveHistory(List<WatchEntry> history) => _prefs.setString(
    _historyKey,
    jsonEncode([for (final e in history) e.toJson()]),
  );

  String getSubtitleLanguage() => _prefs.getString(_subLangKey) ?? 'eng';

  Future<void> saveSubtitleLanguage(String lang) =>
      _prefs.setString(_subLangKey, lang);
}
