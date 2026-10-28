import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/manga_entities.dart';

class MangaLocalDataSource {
  MangaLocalDataSource(this._prefs);

  static const _reposKey = 'manga.repos.v1';
  static const _libraryKey = 'manga.library.v1';
  static const _settingsKey = 'manga.settings.v1';

  final SharedPreferences _prefs;

  List<ExtensionRepo> readRepos() => [
    for (final j in _list(_reposKey))
      ExtensionRepo(
        url: j['url'] as String,
        name: j['name'] as String,
        signingKey: j['signingKey'] as String,
        website: j['website'] as String?,
      ),
  ];

  Future<void> writeRepos(List<ExtensionRepo> repos) => _prefs.setString(
    _reposKey,
    jsonEncode([
      for (final r in repos)
        {
          'url': r.url,
          'name': r.name,
          'signingKey': r.signingKey,
          'website': r.website,
        },
    ]),
  );

  List<LibraryEntry> readLibrary() => [
    for (final j in _list(_libraryKey))
      LibraryEntry(
        manga: Manga.fromMap(
          j['manga']['sourceId'] as String,
          (j['manga'] as Map).cast<Object?, Object?>(),
        ),
        addedAt: DateTime.parse(j['addedAt'] as String),
        lastChapterUrl: j['lastChapterUrl'] as String?,
        lastPage: j['lastPage'] as int? ?? 0,
        lastReadAt: DateTime.tryParse(j['lastReadAt'] as String? ?? ''),
        readChapters: {
          ...(j['readChapters'] as List? ?? const []).cast<String>(),
        },
      ),
  ];

  Future<void> writeLibrary(List<LibraryEntry> library) => _prefs.setString(
    _libraryKey,
    jsonEncode([
      for (final e in library)
        {
          'manga': e.manga.toMap(),
          'addedAt': e.addedAt.toIso8601String(),
          'lastChapterUrl': e.lastChapterUrl,
          'lastPage': e.lastPage,
          'lastReadAt': e.lastReadAt?.toIso8601String(),
          'readChapters': e.readChapters.toList(),
        },
    ]),
  );

  ({bool showNsfw, MangaReadingMode mode, Set<String> langs}) readSettings() {
    final raw = _prefs.getString(_settingsKey);
    final j = raw == null ? const <String, dynamic>{} : jsonDecode(raw);
    return (
      showNsfw: j['showNsfw'] as bool? ?? false,
      mode:
          MangaReadingMode.values.asNameMap()[j['mode']] ??
          MangaReadingMode.rightToLeft,
      langs: {
        ...(j['langs'] as List? ?? const ['all', 'en']).cast<String>(),
      },
    );
  }

  Future<void> writeSettings({
    required bool showNsfw,
    required MangaReadingMode mode,
    required Set<String> langs,
  }) => _prefs.setString(
    _settingsKey,
    jsonEncode({
      'showNsfw': showNsfw,
      'mode': mode.name,
      'langs': langs.toList(),
    }),
  );

  List<Map<String, dynamic>> _list(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return const [];
    }
  }
}
