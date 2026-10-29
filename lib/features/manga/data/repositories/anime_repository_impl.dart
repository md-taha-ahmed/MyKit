import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/anime_entities.dart';
import '../../domain/entities/manga_entities.dart';
import '../../domain/repositories/anime_repository.dart';
import '../datasources/anime_native_data_source.dart';

class AnimeRepositoryImpl implements AnimeRepository {
  AnimeRepositoryImpl(this._prefs, this._native);

  static const _libraryKey = 'anime.library.v1';

  final SharedPreferences _prefs;
  final AnimeNativeDataSource _native;

  @override
  Future<List<InstalledExtension>> installedExtensions() => _native.installed();

  @override
  Future<InstalledExtension> install(AvailableExtension extension) =>
      _native.install(extension);

  @override
  Future<void> uninstall(String pkgName) => _native.uninstall(pkgName);

  @override
  Future<AnimesPage> popular(String sourceId, int page) =>
      _native.popular(sourceId, page);

  @override
  Future<AnimesPage> latest(String sourceId, int page) =>
      _native.latest(sourceId, page);

  @override
  Future<AnimesPage> search(String sourceId, String query, int page) =>
      _native.search(sourceId, query, page);

  @override
  Future<Anime> details(Anime anime) => _native.details(anime);

  @override
  Future<List<AnimeEpisode>> episodes(Anime anime) => _native.episodes(anime);

  @override
  Future<List<Anime>> seasons(Anime anime) => _native.seasons(anime);

  @override
  Future<String> cover(String sourceId, String url) =>
      _native.cover(sourceId, url);

  @override
  Future<String?> webUrl(Anime anime, {AnimeEpisode? episode}) =>
      _native.webUrl(anime, episode: episode);

  @override
  Future<List<AnimeHoster>> hosters(String sourceId, AnimeEpisode episode) =>
      _native.hosters(sourceId, episode);

  @override
  Future<List<AnimeVideo>> hosterVideos(String sourceId, String hoster) =>
      _native.hosterVideos(sourceId, hoster);

  @override
  Future<ResolvedVideo> resolve(String sourceId, String video) =>
      _native.resolve(sourceId, video);

  @override
  List<AnimeLibraryEntry> getLibrary() {
    final raw = _prefs.getString(_libraryKey);
    if (raw == null) return [];
    try {
      return [
        for (final j in jsonDecode(raw) as List)
          AnimeLibraryEntry.fromJson(j as Map<String, dynamic>),
      ];
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> saveLibrary(List<AnimeLibraryEntry> library) => _prefs.setString(
    _libraryKey,
    jsonEncode([for (final e in library) e.toJson()]),
  );
}
