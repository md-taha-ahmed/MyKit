import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';

import '../../../../core/i18n/i18n.dart';
import '../../../manga/domain/entities/anime_entities.dart';
import '../../../manga/domain/entities/manga_entities.dart';
import '../../../manga/domain/repositories/manga_repository.dart';
import '../../../manga/presentation/providers/anime_providers.dart';
import '../../../manga/presentation/providers/manga_providers.dart';
import '../../../movies/data/datasources/torrent_stream_data_source.dart';
import '../../../movies/domain/entities/stremio_entities.dart';
import '../../../movies/presentation/providers/movies_providers.dart';
import '../../data/downloads_store.dart';
import '../../data/media_downloader.dart';
import '../../domain/download_item.dart';

/// Where downloads are saved. Set in `main()` (the app's own folder on the
/// phone storage: no permission needed, removed if the app is uninstalled).
final downloadsDirectoryProvider = Provider<Directory>(
  (ref) => throw UnimplementedError(
    'downloadsDirectoryProvider must be overridden in main()',
  ),
);

final downloadsProvider =
    NotifierProvider<DownloadsNotifier, List<DownloadItem>>(
      DownloadsNotifier.new,
    );

/// The download for one chapter, episode or movie, if any.
final downloadForProvider = Provider.family<DownloadItem?, String>(
  (ref, id) => ref.watch(
    downloadsProvider.select((l) => l.where((i) => i.id == id).firstOrNull),
  ),
);

/// Free space on the storage downloads go to.
final downloadsFreeSpaceProvider = FutureProvider.autoDispose<int?>(
  (ref) =>
      DownloadsNative().freeSpace(ref.read(downloadsDirectoryProvider).path),
);

/// The queue: one download at a time (kind to slow, metered connections),
/// continuing where it stopped after the app or the internet was cut.
class DownloadsNotifier extends Notifier<List<DownloadItem>> {
  late final DownloadsStore _store = DownloadsStore(
    ref.read(downloadsDirectoryProvider),
  );
  final _native = DownloadsNative();
  final _torrents = TorrentStreamDataSource();
  final _downloader = MediaDownloader();

  final _tokens = <String, CancelToken>{};
  String? _running;
  Timer? _wake;
  Timer? _saveTimer;

  /// After a lost connection, nothing starts before this.
  DateTime? _holdUntil;
  int _networkFailures = 0;

  @override
  List<DownloadItem> build() {
    final items = [
      for (final i in _store.load())
        i.state == DownloadState.running
            ? i.copyWith(state: DownloadState.queued)
            : i,
    ];
    ref.onDispose(() {
      _wake?.cancel();
      _saveTimer?.cancel();
    });
    Future.microtask(_pump);
    return items;
  }

  // -------------------------------------------------------------------------
  // Adding
  // -------------------------------------------------------------------------

  static String mangaId(Manga manga, Chapter chapter) =>
      DownloadItem.idFor(DownloadKind.manga, manga.key, chapter.url);

  static String animeId(Anime anime, AnimeEpisode episode) =>
      DownloadItem.idFor(DownloadKind.anime, anime.key, episode.url);

  static String movieId(String metaId, String videoId) =>
      DownloadItem.idFor(DownloadKind.movie, metaId, videoId);

  void addManga(Manga manga, Chapter chapter) => _add(
    DownloadItem(
      id: mangaId(manga, chapter),
      kind: DownloadKind.manga,
      groupKey: manga.key,
      groupTitle: manga.title,
      itemKey: chapter.url,
      itemTitle: chapter.name,
      order: chapter.chapterNumber,
      dir: _store.folderFor(mangaId(manga, chapter)).path,
      addedAt: DateTime.now(),
      coverUrl: manga.thumbnailUrl,
      source: {
        'sourceId': manga.sourceId,
        'manga': manga.toMap(),
        'chapter': chapter.toMap(),
      },
    ),
  );

  void addAnime({
    required Anime anime,
    required AnimeEpisode episode,
    required String videoTitle,
    required ResolvedVideo video,
    String? sourceName,
  }) => _add(
    DownloadItem(
      id: animeId(anime, episode),
      kind: DownloadKind.anime,
      groupKey: anime.key,
      groupTitle: anime.title,
      itemKey: episode.url,
      itemTitle: episode.name,
      order: episode.episodeNumber,
      dir: _store.folderFor(animeId(anime, episode)).path,
      addedAt: DateTime.now(),
      coverUrl: anime.thumbnailUrl,
      source: {
        'anime': anime.toJson(),
        'episode': episode.toMap(),
        'videoTitle': videoTitle,
        'sourceName': sourceName,
        ..._resolvedToJson(video),
      },
    ),
  );

  void addMovie({
    required String type,
    required String metaId,
    required String videoId,
    required String name,
    required StreamSource source,
    String? poster,
    String? background,
    String? episodeLabel,
  }) {
    final parts = videoId.split(':');
    final order = parts.length >= 3
        ? (int.tryParse(parts[parts.length - 2]) ?? 0) * 10000.0 +
              (int.tryParse(parts.last) ?? 0)
        : 0.0;
    _add(
      DownloadItem(
        id: movieId(metaId, videoId),
        kind: DownloadKind.movie,
        groupKey: metaId,
        groupTitle: name,
        itemKey: videoId,
        itemTitle: episodeLabel ?? '',
        order: order,
        dir: _store.folderFor(movieId(metaId, videoId)).path,
        addedAt: DateTime.now(),
        coverUrl: poster,
        source: {
          'type': type,
          'metaId': metaId,
          'videoId': videoId,
          'name': name,
          'poster': poster,
          'background': background,
          'episodeLabel': episodeLabel,
          'release': source.release,
          'url': source.url,
          'infoHash': source.infoHash,
          'fileIdx': source.fileIdx,
          'trackers': source.trackers,
          'filename': source.filename,
        },
      ),
    );
  }

  static Map<String, Object?> _resolvedToJson(ResolvedVideo v) => {
    'url': v.url,
    'headers': v.headers,
    'subtitles': [
      for (final s in v.subtitles) {'url': s.url, 'lang': s.lang},
    ],
    'audios': [
      for (final a in v.audios) {'url': a.url, 'lang': a.lang},
    ],
  };

  void _add(DownloadItem item) {
    final existing = state.where((i) => i.id == item.id).firstOrNull;
    if (existing != null) {
      // Already saved or on its way; a failed one starts again.
      if (existing.state == DownloadState.failed ||
          existing.state == DownloadState.paused) {
        resume(existing.id);
      }
      return;
    }
    final cover = state
        .where((i) => i.groupKey == item.groupKey && i.coverPath != null)
        .firstOrNull
        ?.coverPath;
    _set([...state, item.copyWith(coverPath: cover)]);
    if (cover == null) unawaited(_saveCover(item));
    _pump();
  }

  // -------------------------------------------------------------------------
  // Controls
  // -------------------------------------------------------------------------

  void pause(String id) {
    _update(id, (i) => i.isDone ? i : i.copyWith(state: DownloadState.paused));
    _tokens[id]?.cancel();
    _pump();
  }

  void resume(String id) {
    _holdUntil = null;
    _networkFailures = 0;
    _update(
      id,
      (i) => i.isDone
          ? i
          : i.copyWith(
              state: DownloadState.queued,
              clearError: true,
              clearRetry: true,
            ),
    );
    _pump();
  }

  void pauseAll() {
    for (final i in state) {
      if (i.isActive) pause(i.id);
    }
  }

  void resumeAll() {
    for (final i in state) {
      if (i.state == DownloadState.paused || i.state == DownloadState.failed) {
        resume(i.id);
      }
    }
  }

  Future<void> delete(String id) async {
    final item = state.where((i) => i.id == id).firstOrNull;
    if (item == null) return;
    _tokens[id]?.cancel();
    _set([
      for (final i in state)
        if (i.id != id) i,
    ]);
    final hash = item.source['infoHash'] as String?;
    if (hash != null) {
      try {
        await _torrents.stopDownload(hash);
      } catch (_) {}
    }
    // Let a running download close its files first.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    try {
      await Directory(item.dir).delete(recursive: true);
    } catch (_) {}
    if (item.coverPath != null &&
        !state.any((i) => i.coverPath == item.coverPath)) {
      try {
        await File(item.coverPath!).delete();
      } catch (_) {}
    }
    _pump();
  }

  Future<void> deleteGroup(String groupKey) async {
    final ids = [
      for (final i in state)
        if (i.groupKey == groupKey) i.id,
    ];
    await Future.wait(ids.map(delete));
  }

  // -------------------------------------------------------------------------
  // State
  // -------------------------------------------------------------------------

  void _set(List<DownloadItem> items) {
    state = items;
    _scheduleSave();
    _syncNotification();
  }

  void _update(String id, DownloadItem Function(DownloadItem) change) {
    if (!state.any((i) => i.id == id)) return;
    _set([for (final i in state) i.id == id ? change(i) : i]);
  }

  void _scheduleSave() {
    if (_saveTimer?.isActive ?? false) return;
    _saveTimer = Timer(const Duration(seconds: 2), () => _store.save(state));
  }

  DateTime _lastNotice = DateTime(0);

  void _syncNotification({bool force = false}) {
    final active = state.where((i) => i.isActive).toList();
    if (active.isEmpty) {
      unawaited(_native.release());
      return;
    }
    final now = DateTime.now();
    if (!force && now.difference(_lastNotice) < const Duration(seconds: 2)) {
      return;
    }
    _lastNotice = now;
    final running = active
        .where((i) => i.state == DownloadState.running)
        .firstOrNull;
    final title = tr('Downloading {n}', {'n': active.length});
    if (running == null) {
      unawaited(_native.keepAlive(title, tr('Waiting for the internet…'), -1));
      return;
    }
    final name = [
      running.groupTitle,
      if (running.itemTitle.isNotEmpty) running.itemTitle,
    ].join(' · ');
    unawaited(
      _native.keepAlive(
        title,
        '$name · ${(running.progress * 100).round()}%',
        (running.progress * 100).round(),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Running
  // -------------------------------------------------------------------------

  void _pump() {
    _wake?.cancel();
    if (_running != null) return;
    final now = DateTime.now();
    final hold = _holdUntil;
    if (hold != null && hold.isAfter(now)) {
      if (state.any((i) => i.state == DownloadState.queued)) {
        _wake = Timer(hold.difference(now), _pump);
      }
      return;
    }
    final queued = state.where((i) => i.state == DownloadState.queued).toList()
      ..sort((a, b) => a.addedAt.compareTo(b.addedAt));
    if (queued.isEmpty) {
      _syncNotification(force: true);
      return;
    }
    unawaited(_run(queued.first));
  }

  Future<void> _run(DownloadItem item) async {
    final token = CancelToken();
    _tokens[item.id] = token;
    _running = item.id;
    _update(
      item.id,
      (i) => i.copyWith(
        state: DownloadState.running,
        clearError: true,
        clearRetry: true,
      ),
    );
    _syncNotification(force: true);
    try {
      final result = switch (item.kind) {
        DownloadKind.manga => await _runManga(item, token),
        DownloadKind.anime => await _runAnime(item, token),
        DownloadKind.movie => await _runMovie(item, token),
      };
      token.check();
      final size = await folderSize(Directory(item.dir));
      _networkFailures = 0;
      _update(
        item.id,
        (i) => i.copyWith(
          state: DownloadState.done,
          progress: 1,
          bytes: size,
          result: result,
          clearError: true,
        ),
      );
    } on DownloadCancelled {
      // Paused or deleted; that already set the state.
    } catch (e) {
      if (token.cancelled) {
        // Same: the error came from stopping it.
      } else if (_looksLikeNetwork(e)) {
        _networkFailures++;
        final wait = Duration(
          seconds: (15 * (1 << (_networkFailures - 1).clamp(0, 5))).clamp(
            15,
            300,
          ),
        );
        _holdUntil = DateTime.now().add(wait);
        _update(
          item.id,
          (i) => i.copyWith(
            state: DownloadState.queued,
            error: tr('No internet. Trying again by itself.'),
            retryAt: _holdUntil,
          ),
        );
      } else {
        _update(
          item.id,
          (i) => i.copyWith(state: DownloadState.failed, error: _message(e)),
        );
      }
    } finally {
      _tokens.remove(item.id);
      _running = null;
      _pump();
    }
  }

  DateTime _lastProgress = DateTime(0);

  void _progress(String id, double fraction, int bytes) {
    final now = DateTime.now();
    if (fraction < 1 &&
        now.difference(_lastProgress) < const Duration(milliseconds: 600)) {
      return;
    }
    _lastProgress = now;
    _update(
      id,
      (i) => i.copyWith(progress: fraction.clamp(0, 1), bytes: bytes),
    );
  }

  // -- Manga --------------------------------------------------------------

  Future<Map<String, Object?>> _runManga(
    DownloadItem item,
    CancelToken token,
  ) async {
    final repo = ref.read(mangaRepositoryProvider);
    final sourceId = item.source['sourceId'] as String;
    final chapter = Chapter.fromMap(item.source['chapter'] as Map);
    final pages = await repo.pages(sourceId, chapter);
    token.check();
    if (pages.isEmpty) throw DownloadFailure(tr('This chapter has no pages.'));
    final dir = Directory(item.dir);
    await dir.create(recursive: true);
    final paths = <String>[];
    var bytes = 0;
    for (final page in pages) {
      token.check();
      final target = File(
        '${dir.path}/${(paths.length + 1).toString().padLeft(4, '0')}',
      );
      if (!await target.exists() || await target.length() == 0) {
        final cached = await repo.pageImage(sourceId, page);
        token.check();
        await File(cached).copy(target.path);
      }
      bytes += await target.length();
      paths.add(target.path);
      _progress(item.id, paths.length / pages.length, bytes);
    }
    return {'pages': paths};
  }

  // -- Anime --------------------------------------------------------------

  Future<Map<String, Object?>> _runAnime(
    DownloadItem item,
    CancelToken token,
  ) async {
    var source = item.source;
    final dir = Directory(item.dir);
    SavedVideo video;
    try {
      video = await _video(item.id, source, dir, token);
    } on HttpStatusError catch (e) {
      if (isNetworkError(e)) rethrow;
      // Links from anime sites expire: ask the source for a fresh one.
      source = await _refreshAnime(source);
      token.check();
      _update(item.id, (i) => i.copyWith(source: source));
      await _clearPartial(dir);
      video = await _video(item.id, source, dir, token);
    }
    final headers = _headers(source);
    final subs = <Map<String, String>>[];
    var n = 0;
    for (final s in (source['subtitles'] as List? ?? const []).cast<Map>()) {
      n++;
      final url = s['url'] as String;
      final target = File('${dir.path}/sub_$n.${_subExtension(url)}');
      try {
        if (!await target.exists()) {
          await _downloader.downloadSmall(
            url: url,
            headers: headers,
            target: target,
            token: token,
          );
        }
        subs.add({'path': target.path, 'lang': s['lang'] as String? ?? ''});
      } on DownloadCancelled {
        rethrow;
      } catch (_) {
        // A missing subtitle doesn't stop the episode.
      }
    }
    final audios = <Map<String, String>>[
      if (video.audio != null) {'path': video.audio!, 'lang': ''},
    ];
    n = 0;
    for (final a in (source['audios'] as List? ?? const []).cast<Map>()) {
      n++;
      final saved = await _downloader.downloadVideo(
        url: a['url'] as String,
        headers: headers,
        dir: Directory('${dir.path}/audio_$n'),
        token: token,
        onProgress: (_, _) {},
      );
      audios.add({'path': saved.video, 'lang': a['lang'] as String? ?? ''});
    }
    return {'video': video.video, 'subtitles': subs, 'audios': audios};
  }

  Future<SavedVideo> _video(
    String id,
    Map<String, Object?> source,
    Directory dir,
    CancelToken token,
  ) => _downloader.downloadVideo(
    url: source['url'] as String,
    headers: _headers(source),
    dir: dir,
    token: token,
    onProgress: (f, b) => _progress(id, f, b),
  );

  static Map<String, String> _headers(Map<String, Object?> source) => {
    for (final e in ((source['headers'] as Map?) ?? const {}).entries)
      e.key as String: e.value as String,
  };

  /// Picks the same video again (same name), else the source's best one.
  Future<Map<String, Object?>> _refreshAnime(
    Map<String, Object?> source,
  ) async {
    final repo = ref.read(animeRepositoryProvider);
    final anime = Anime.fromJson(
      Map<String, dynamic>.from(source['anime'] as Map),
    );
    final episode = AnimeEpisode.fromMap(source['episode'] as Map);
    final wanted = source['videoTitle'] as String? ?? '';
    final hosters = await repo.hosters(anime.sourceId, episode);
    final videos = [for (final h in hosters) ...?h.videos];
    var pick = videos.where((v) => v.title == wanted).firstOrNull;
    if (pick == null) {
      for (final h in hosters.where((h) => h.videos == null)) {
        final more = await repo.hosterVideos(anime.sourceId, h.token);
        videos.addAll(more);
        pick = more.where((v) => v.title == wanted).firstOrNull;
        if (pick != null) break;
      }
    }
    pick ??= videos.firstOrNull;
    if (pick == null) {
      throw DownloadFailure(tr('No videos found for this episode.'));
    }
    final resolved = await repo.resolve(anime.sourceId, pick.token);
    return {...source, ..._resolvedToJson(resolved), 'videoTitle': pick.title};
  }

  static Future<void> _clearPartial(Directory dir) async {
    if (!await dir.exists()) return;
    await for (final f in dir.list()) {
      final name = f.path.split('/').last;
      if (name.startsWith('video.') || name.startsWith('audio')) {
        await f.delete(recursive: true);
      }
    }
  }

  static String _subExtension(String url) {
    final ext = Uri.parse(url).path.split('.').last.toLowerCase();
    return const {'srt', 'vtt', 'ass', 'ssa'}.contains(ext) ? ext : 'srt';
  }

  // -- Movies -------------------------------------------------------------

  Future<Map<String, Object?>> _runMovie(
    DownloadItem item,
    CancelToken token,
  ) async {
    final src = item.source;
    final dir = Directory(item.dir);
    await dir.create(recursive: true);
    final String video;
    final hash = src['infoHash'] as String?;
    if (hash != null) {
      video = await _torrent(item, hash, token);
    } else {
      final url = src['url'] as String?;
      if (url == null) {
        throw DownloadFailure(tr('This source can\'t be downloaded.'));
      }
      video = (await _downloader.downloadVideo(
        url: url,
        headers: const {},
        dir: dir,
        token: token,
        onProgress: (f, b) => _progress(item.id, f, b),
      )).video;
    }
    final subtitles = await _movieSubtitles(item, token);
    return {'video': video, 'subtitles': subtitles};
  }

  Future<String> _torrent(
    DownloadItem item,
    String hash,
    CancelToken token,
  ) async {
    final src = item.source;
    final stream = StreamSource(
      addonName: '',
      name: '',
      title: '',
      infoHash: hash,
      fileIdx: (src['fileIdx'] as num?)?.toInt(),
      sources: [
        for (final t in (src['trackers'] as List? ?? const []).cast<String>())
          'tracker:$t',
      ],
      filename: src['filename'] as String?,
    );
    final folder = '${item.dir}/torrent';
    try {
      var status = await _torrents.download(stream, folder);
      while (true) {
        if (token.cancelled) {
          await _torrents.stopDownload(hash);
          throw const DownloadCancelled();
        }
        if (status.state == 'error') {
          throw DownloadFailure(status.error ?? tr('Torrent failed.'));
        }
        if (status.state == 'done' && status.path != null) return status.path!;
        _progress(
          item.id,
          status.progress,
          (status.progress * status.fileSize).round(),
        );
        await Future<void>.delayed(const Duration(seconds: 2));
        status =
            await _torrents.downloadStatus(hash) ??
            await _torrents.download(stream, folder);
      }
    } on PlatformException catch (e) {
      throw DownloadFailure(e.message ?? e.code);
    }
  }

  /// Subtitles in the chosen language and English, from the subtitle add-ons.
  Future<List<Map<String, String>>> _movieSubtitles(
    DownloadItem item,
    CancelToken token,
  ) async {
    final saved = <Map<String, String>>[];
    try {
      final addons = await ref.read(loadedAddonsProvider.future);
      final all = await ref
          .read(moviesRepositoryProvider)
          .subtitles(
            addons,
            item.source['type'] as String,
            item.source['videoId'] as String,
          )
          .timeout(const Duration(seconds: 30));
      final wanted = {ref.read(subtitleLanguageProvider), 'eng'};
      final counts = <String, int>{};
      for (final s in all) {
        final lang = languageCode(s.lang);
        if (!wanted.contains(lang)) continue;
        if ((counts[lang] ?? 0) >= 2) continue;
        counts[lang] = (counts[lang] ?? 0) + 1;
        final target = File(
          '${item.dir}/sub_${saved.length + 1}.${_subExtension(s.url)}',
        );
        try {
          await _downloader.downloadSmall(
            url: s.url,
            headers: const {},
            target: target,
            token: token,
          );
          saved.add({'path': target.path, 'lang': s.lang});
        } on DownloadCancelled {
          rethrow;
        } catch (_) {}
      }
    } on DownloadCancelled {
      rethrow;
    } catch (_) {
      // Subtitles are a bonus; the video is what matters.
    }
    return saved;
  }

  // -- Covers -------------------------------------------------------------

  Future<void> _saveCover(DownloadItem item) async {
    final url = item.coverUrl;
    if (url == null || url.isEmpty) return;
    try {
      final target = File(
        '${_store.covers.path}/${sha1.convert(utf8.encode(item.groupKey)).toString().substring(0, 16)}',
      );
      if (!await target.exists()) {
        await target.parent.create(recursive: true);
        switch (item.kind) {
          case DownloadKind.manga:
            final path = await ref
                .read(mangaRepositoryProvider)
                .cover(item.source['sourceId'] as String, url);
            await File(path).copy(target.path);
          case DownloadKind.anime:
            final anime = item.source['anime'] as Map;
            final path = await ref
                .read(animeRepositoryProvider)
                .cover(anime['sourceId'] as String, url);
            await File(path).copy(target.path);
          case DownloadKind.movie:
            await _downloader.downloadSmall(
              url: url,
              headers: const {},
              target: target,
              token: CancelToken(),
            );
        }
      }
      _set([
        for (final i in state)
          i.groupKey == item.groupKey ? i.copyWith(coverPath: target.path) : i,
      ]);
    } catch (_) {
      // No cover offline; the title still shows.
    }
  }

  // -- Errors -------------------------------------------------------------

  static bool _looksLikeNetwork(Object e) {
    if (isNetworkError(e)) return true;
    if (e is MangaException) {
      final text = '${e.message} ${e.details ?? ''}';
      const hints = [
        'UnknownHost',
        'Unable to resolve host',
        'SocketTimeout',
        'timeout',
        'ConnectException',
        'Failed to connect',
        'Connection reset',
        'SSLException',
        'SocketException',
        'Network is unreachable',
      ];
      return hints.any(text.contains);
    }
    return false;
  }

  static String _message(Object e) => switch (e) {
    HttpStatusError(:final code) when code == 403 || code == 410 => tr(
      'The link expired. Download it again from the title.',
    ),
    HttpStatusError(:final code) when code == 404 => tr(
      'The file is gone from the site. Try another source.',
    ),
    _ => '$e',
  };
}
