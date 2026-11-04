import 'dart:async';

import '../../../../core/i18n/i18n.dart';
import '../../domain/entities/stremio_entities.dart';
import '../../domain/entities/torrent_stream_status.dart';
import '../../domain/repositories/movies_repository.dart';
import '../datasources/movies_local_data_source.dart';
import '../datasources/stremio_addon_client.dart';
import '../datasources/torrent_stream_data_source.dart';

class MoviesRepositoryImpl implements MoviesRepository {
  MoviesRepositoryImpl(this._local, this._addons, this._torrent);

  final MoviesLocalDataSource _local;
  final StremioAddonClient _addons;
  final TorrentStreamDataSource _torrent;

  @override
  List<String> getAddonUrls() => _local.getAddonUrls();

  @override
  Future<void> saveAddonUrls(List<String> manifestUrls) =>
      _local.saveAddonUrls(manifestUrls);

  @override
  Future<AddonManifest> fetchManifest(String manifestUrl) =>
      _addons.manifest(manifestUrl);

  @override
  Future<List<MetaPreview>> catalog(CatalogDef catalog, {int skip = 0}) =>
      _addons.catalog(
        catalog.addonUrl,
        catalog.type,
        catalog.id,
        extra: skip > 0 ? {'skip': '$skip'} : const {},
      );

  @override
  Future<List<MetaPreview>> search(
    List<AddonManifest> addons,
    MediaType type,
    String query,
  ) async {
    // An IMDb id or link (e.g. imdb.com/title/tt1254207) opens that title.
    final imdbId = RegExp(r'\btt\d{5,}\b').firstMatch(query)?.group(0);
    if (imdbId != null) {
      try {
        return [(await meta(addons, type.id, imdbId)).preview];
      } catch (_) {
        return const [];
      }
    }
    final searchable = [
      for (final a in addons)
        for (final c in a.catalogs)
          if (c.type == type.id && c.searchable) c,
    ];
    // One catalog per add-on is enough (Cinemeta has several searchable ones).
    final seenAddons = <String>{};
    final results = await Future.wait([
      for (final c in searchable)
        if (seenAddons.add(c.addonUrl))
          _addons
              .catalog(c.addonUrl, c.type, c.id, extra: {'search': query})
              .catchError((_) => <MetaPreview>[]),
    ]);
    final seen = <String>{};
    return [
      for (final list in results)
        for (final m in list)
          if (seen.add(m.id)) m,
    ];
  }

  @override
  Future<MetaDetail> meta(
    List<AddonManifest> addons,
    String type,
    String id,
  ) async {
    Object? lastError;
    for (final a in addons.where((a) => a.supports('meta', type, id))) {
      try {
        final meta = await _addons.meta(a.transportUrl, type, id);
        if (meta != null) return meta;
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError is MoviesException
        ? lastError
        : MoviesException(tr('No add-on has details for this title.'));
  }

  @override
  Stream<List<StreamSource>> streams(
    List<AddonManifest> addons,
    String type,
    String videoId,
  ) {
    final sources = addons
        .where((a) => a.supports('stream', type, videoId))
        .toList();
    final controller = StreamController<List<StreamSource>>();
    if (sources.isEmpty) {
      controller.addError(
        MoviesException(tr('No stream add-on installed for this title.')),
      );
      controller.close();
      return controller.stream;
    }
    final all = <StreamSource>[];
    var pending = sources.length;
    Object? lastError;
    for (final a in sources) {
      _addons
          .streams(a, type, videoId)
          .then((list) {
            all.addAll(list.where((s) => s.isPlayable));
            controller.add(List.unmodifiable(all));
          })
          .catchError((Object e) {
            lastError = e;
          })
          .whenComplete(() {
            pending--;
            if (pending == 0) {
              if (all.isEmpty && lastError != null) {
                controller.addError(lastError!);
              } else {
                controller.add(List.unmodifiable(all));
              }
              controller.close();
            }
          });
    }
    return controller.stream;
  }

  @override
  Future<List<SubtitleInfo>> subtitles(
    List<AddonManifest> addons,
    String type,
    String videoId,
  ) async {
    final results = await Future.wait([
      for (final a in addons.where(
        (a) => a.supports('subtitles', type, videoId),
      ))
        _addons.subtitles(a, type, videoId).catchError((_) => <SubtitleInfo>[]),
    ]);
    return [for (final list in results) ...list];
  }

  @override
  Future<TorrentStreamStatus> startTorrent(StreamSource source) =>
      _torrent.start(source);

  @override
  Future<TorrentStreamStatus?> torrentStatus(String id) => _torrent.status(id);

  @override
  Future<void> stopTorrent(String id) => _torrent.stop(id);

  @override
  Future<void> warmUpTorrents() => _torrent.warmUp();

  @override
  List<WatchEntry> getHistory() => _local.getHistory();

  @override
  Future<void> saveHistory(List<WatchEntry> history) =>
      _local.saveHistory(history);

  @override
  String getSubtitleLanguage() => _local.getSubtitleLanguage();

  @override
  Future<void> saveSubtitleLanguage(String lang) =>
      _local.saveSubtitleLanguage(lang);
}
