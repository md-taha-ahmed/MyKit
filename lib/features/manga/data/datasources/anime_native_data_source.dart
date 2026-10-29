import 'package:flutter/services.dart';

import '../../domain/entities/anime_entities.dart';
import '../../domain/entities/manga_entities.dart';
import '../../domain/repositories/manga_repository.dart';
import 'manga_native_data_source.dart';

/// Talks to the native anime extension host
/// (`android/.../manga/AnimeChannel.kt` + `ExtensionHost.kt`).
class AnimeNativeDataSource {
  static const _channel = MethodChannel('com.mdtaha.mykit/anime');

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw MangaException(e.message ?? e.code, details: e.details as String?);
    }
  }

  Future<List<InstalledExtension>> installed() async {
    final raw = await _call<List<Object?>>('installed') ?? const [];
    return raw
        .cast<Map<Object?, Object?>>()
        .map(MangaNativeDataSource.extensionFromMap)
        .toList();
  }

  Future<InstalledExtension> install(AvailableExtension ext) async {
    final raw = await _call<Map<Object?, Object?>>('install', {
      'apkUrl': ext.apkUrl,
      'pkgName': ext.pkgName,
      'signingKey': ext.repo.signingKey,
    });
    return MangaNativeDataSource.extensionFromMap(raw!);
  }

  Future<void> uninstall(String pkgName) =>
      _call<void>('uninstall', {'pkgName': pkgName});

  Future<AnimesPage> popular(String sourceId, int page) =>
      _page('popular', {'sourceId': sourceId, 'page': page}, sourceId);

  Future<AnimesPage> latest(String sourceId, int page) =>
      _page('latest', {'sourceId': sourceId, 'page': page}, sourceId);

  Future<AnimesPage> search(String sourceId, String query, int page) => _page(
    'search',
    {'sourceId': sourceId, 'query': query, 'page': page},
    sourceId,
  );

  Future<Anime> details(Anime anime) async {
    final raw = await _call<Map<Object?, Object?>>('details', {
      'sourceId': anime.sourceId,
      'anime': anime.toMap(),
    });
    return Anime.fromMap(anime.sourceId, raw!);
  }

  Future<List<AnimeEpisode>> episodes(Anime anime) async {
    final raw = await _call<List<Object?>>('episodes', {
      'sourceId': anime.sourceId,
      'anime': anime.toMap(),
    });
    return (raw ?? const [])
        .cast<Map<Object?, Object?>>()
        .map(AnimeEpisode.fromMap)
        .toList();
  }

  Future<List<Anime>> seasons(Anime anime) async {
    final raw = await _call<List<Object?>>('seasons', {
      'sourceId': anime.sourceId,
      'anime': anime.toMap(),
    });
    return [
      for (final m in (raw ?? const []).cast<Map<Object?, Object?>>())
        Anime.fromMap(anime.sourceId, m),
    ];
  }

  Future<List<AnimeHoster>> hosters(String sourceId, AnimeEpisode ep) async {
    final raw = await _call<List<Object?>>('hosters', {
      'sourceId': sourceId,
      'episode': ep.toMap(),
    });
    return (raw ?? const [])
        .cast<Map<Object?, Object?>>()
        .map(AnimeHoster.fromMap)
        .toList();
  }

  Future<List<AnimeVideo>> hosterVideos(String sourceId, String hoster) async {
    final raw = await _call<List<Object?>>('hosterVideos', {
      'sourceId': sourceId,
      'hoster': hoster,
    });
    return (raw ?? const [])
        .cast<Map<Object?, Object?>>()
        .map(AnimeVideo.fromMap)
        .toList();
  }

  Future<ResolvedVideo> resolve(String sourceId, String video) async =>
      ResolvedVideo.fromMap(
        (await _call<Map<Object?, Object?>>('resolve', {
          'sourceId': sourceId,
          'video': video,
        }))!,
      );

  /// Local file path of the downloaded cover.
  Future<String> cover(String sourceId, String url) async =>
      (await _call<String>('cover', {'sourceId': sourceId, 'url': url}))!;

  Future<String?> webUrl(Anime anime, {AnimeEpisode? episode}) =>
      _call<String>('webUrl', {
        'sourceId': anime.sourceId,
        'anime': anime.toMap(),
        'episode': episode?.toMap(),
      });

  Future<AnimesPage> _page(
    String method,
    Map<String, Object?> args,
    String sourceId,
  ) async {
    final raw = (await _call<Map<Object?, Object?>>(method, args))!;
    return AnimesPage([
      for (final m in (raw['animes'] as List).cast<Map<Object?, Object?>>())
        Anime.fromMap(sourceId, m),
    ], raw['hasNextPage'] as bool? ?? false);
  }
}
