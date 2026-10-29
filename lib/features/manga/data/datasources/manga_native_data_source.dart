import 'package:flutter/services.dart';

import '../../domain/entities/manga_entities.dart';
import '../../domain/repositories/manga_repository.dart';

/// Talks to the native extension host
/// (`android/.../manga/MangaChannel.kt` + `ExtensionHost.kt`).
class MangaNativeDataSource {
  static const _channel = MethodChannel('com.mdtaha.mykit/manga');

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw MangaException(e.message ?? e.code, details: e.details as String?);
    }
  }

  Future<List<InstalledExtension>> installed() async {
    final raw = await _call<List<Object?>>('installed') ?? const [];
    return raw.cast<Map<Object?, Object?>>().map(extensionFromMap).toList();
  }

  Future<InstalledExtension> install(AvailableExtension ext) async {
    final raw = await _call<Map<Object?, Object?>>('install', {
      'apkUrl': ext.apkUrl,
      'pkgName': ext.pkgName,
      'signingKey': ext.repo.signingKey,
    });
    return extensionFromMap(raw!);
  }

  Future<void> uninstall(String pkgName) =>
      _call<void>('uninstall', {'pkgName': pkgName});

  Future<MangasPage> popular(String sourceId, int page) =>
      _page('popular', {'sourceId': sourceId, 'page': page}, sourceId);

  Future<MangasPage> latest(String sourceId, int page) =>
      _page('latest', {'sourceId': sourceId, 'page': page}, sourceId);

  Future<MangasPage> search(String sourceId, String query, int page) => _page(
    'search',
    {'sourceId': sourceId, 'query': query, 'page': page},
    sourceId,
  );

  Future<Manga> details(Manga manga) async {
    final raw = await _call<Map<Object?, Object?>>('details', {
      'sourceId': manga.sourceId,
      'manga': manga.toMap(),
    });
    return Manga.fromMap(manga.sourceId, raw!);
  }

  Future<List<Chapter>> chapters(Manga manga) async {
    final raw = await _call<List<Object?>>('chapters', {
      'sourceId': manga.sourceId,
      'manga': manga.toMap(),
    });
    return (raw ?? const [])
        .cast<Map<Object?, Object?>>()
        .map(Chapter.fromMap)
        .toList();
  }

  Future<List<ReaderPage>> pages(String sourceId, Chapter chapter) async {
    final raw = await _call<List<Object?>>('pages', {
      'sourceId': sourceId,
      'chapter': chapter.toMap(),
    });
    return [
      for (final p in (raw ?? const []).cast<Map<Object?, Object?>>())
        ReaderPage(
          index: (p['index'] as num).toInt(),
          url: p['url'] as String? ?? '',
          imageUrl: p['imageUrl'] as String?,
        ),
    ];
  }

  /// Local file path of the downloaded page image.
  Future<String> pageImage(String sourceId, ReaderPage page) async =>
      (await _call<String>('image', {
        'sourceId': sourceId,
        'page': page.toMap(),
      }))!;

  /// Local file path of the downloaded cover.
  Future<String> cover(String sourceId, String url) async =>
      (await _call<String>('cover', {'sourceId': sourceId, 'url': url}))!;

  Future<String?> webUrl(Manga manga, {Chapter? chapter}) =>
      _call<String>('webUrl', {
        'sourceId': manga.sourceId,
        'manga': manga.toMap(),
        'chapter': chapter?.toMap(),
      });

  Future<MangasPage> _page(
    String method,
    Map<String, Object?> args,
    String sourceId,
  ) async {
    final raw = (await _call<Map<Object?, Object?>>(method, args))!;
    return MangasPage([
      for (final m in (raw['mangas'] as List).cast<Map<Object?, Object?>>())
        Manga.fromMap(sourceId, m),
    ], raw['hasNextPage'] as bool? ?? false);
  }

  static InstalledExtension extensionFromMap(Map<Object?, Object?> m) {
    final name = m['name'] as String;
    final pkg = m['pkgName'] as String;
    final nsfw = m['nsfw'] as bool? ?? false;
    return InstalledExtension(
      pkgName: pkg,
      name: name,
      versionName: m['versionName'] as String? ?? '',
      versionCode: (m['versionCode'] as num?)?.toInt() ?? 0,
      libVersion: (m['libVersion'] as num?)?.toDouble() ?? 0,
      nsfw: nsfw,
      sources: [
        for (final s in (m['sources'] as List).cast<Map<Object?, Object?>>())
          MangaSource(
            id: s['id'] as String,
            name: s['name'] as String,
            lang: s['lang'] as String? ?? '',
            supportsLatest: s['supportsLatest'] as bool? ?? false,
            baseUrl: s['baseUrl'] as String?,
            extensionName: name,
            pkgName: pkg,
            nsfw: nsfw,
          ),
      ],
    );
  }
}
