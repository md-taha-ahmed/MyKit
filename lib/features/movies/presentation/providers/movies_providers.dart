import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../../core/storage/shared_preferences_provider.dart';
import '../../data/datasources/movies_local_data_source.dart';
import '../../data/datasources/stremio_addon_client.dart';
import '../../data/datasources/torrent_stream_data_source.dart';
import '../../data/repositories/movies_repository_impl.dart';
import '../../domain/entities/stremio_entities.dart';
import '../../domain/repositories/movies_repository.dart';

const moviesAccent = Color(0xFF8A5CF6);

// ---------------------------------------------------------------------------
// Dependencies
// ---------------------------------------------------------------------------

final moviesRepositoryProvider = Provider<MoviesRepository>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return MoviesRepositoryImpl(
    MoviesLocalDataSource(ref.watch(sharedPreferencesProvider)),
    StremioAddonClient(client),
    TorrentStreamDataSource(),
  );
});

// ---------------------------------------------------------------------------
// Add-ons
// ---------------------------------------------------------------------------

final addonUrlsProvider = NotifierProvider<AddonUrlsNotifier, List<String>>(
  AddonUrlsNotifier.new,
);

class AddonUrlsNotifier extends Notifier<List<String>> {
  MoviesRepository get _repo => ref.read(moviesRepositoryProvider);

  @override
  List<String> build() => _repo.getAddonUrls();

  void _save(List<String> urls) {
    state = urls;
    _repo.saveAddonUrls(urls);
  }

  /// Validates the manifest, then installs it. Returns the add-on.
  Future<AddonManifest> install(String input) async {
    final url = StremioAddonClient.normalizeManifestUrl(input);
    final manifest = await _repo.fetchManifest(url);
    // A reconfigured add-on (same id, new URL) replaces the old one.
    final loaded = ref.read(addonsProvider).value ?? const [];
    final sameId = loaded
        .where((a) => a.manifest?.id == manifest.id)
        .map((a) => a.url);
    _save([
      for (final u in state)
        if (u != url && !sameId.contains(u)) u,
      url,
    ]);
    return manifest;
  }

  void remove(String url) => _save([...state]..remove(url));

  void reorder(int oldIndex, int newIndex) {
    final list = [...state];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, item);
    _save(list);
  }

  void resetToDefaults() => _save(defaultAddonUrls);
}

typedef AddonState = ({String url, AddonManifest? manifest, String? error});

/// Every configured add-on with its manifest (or why it failed to load).
final addonsProvider = FutureProvider<List<AddonState>>((ref) async {
  final repo = ref.watch(moviesRepositoryProvider);
  final urls = ref.watch(addonUrlsProvider);
  return Future.wait([
    for (final url in urls)
      repo
          .fetchManifest(url)
          .then<AddonState>((m) => (url: url, manifest: m, error: null))
          .catchError(
            (Object e) => (url: url, manifest: null, error: e.toString()),
          ),
  ]);
});

/// Successfully loaded add-ons, in the user's order.
final loadedAddonsProvider = FutureProvider<List<AddonManifest>>((ref) async {
  final states = await ref.watch(addonsProvider.future);
  return [
    for (final s in states)
      if (s.manifest != null) s.manifest!,
  ];
});

/// Browsable catalogs of a type (e.g. Cinemeta's Popular / New / Featured).
final catalogsProvider = FutureProvider.family<List<CatalogDef>, MediaType>((
  ref,
  type,
) async {
  final addons = await ref.watch(loadedAddonsProvider.future);
  return [
    for (final a in addons)
      for (final c in a.catalogs)
        if (c.type == type.id && c.browsable) c,
  ];
});

// ---------------------------------------------------------------------------
// Content
// ---------------------------------------------------------------------------

final catalogItemsProvider =
    FutureProvider.family<List<MetaPreview>, CatalogDef>(
      (ref, catalog) => ref.watch(moviesRepositoryProvider).catalog(catalog),
    );

final searchResultsProvider = FutureProvider.autoDispose
    .family<List<MetaPreview>, ({MediaType type, String query})>((
      ref,
      arg,
    ) async {
      final addons = await ref.watch(loadedAddonsProvider.future);
      return ref
          .watch(moviesRepositoryProvider)
          .search(addons, arg.type, arg.query);
    });

final metaProvider = FutureProvider.autoDispose
    .family<MetaDetail, ({String type, String id})>((ref, arg) async {
      final addons = await ref.watch(loadedAddonsProvider.future);
      ref.keepAlive();
      return ref.watch(moviesRepositoryProvider).meta(addons, arg.type, arg.id);
    });

final streamsProvider = StreamProvider.autoDispose
    .family<List<StreamSource>, ({String type, String videoId})>((
      ref,
      arg,
    ) async* {
      final addons = await ref.watch(loadedAddonsProvider.future);
      yield* ref
          .watch(moviesRepositoryProvider)
          .streams(addons, arg.type, arg.videoId);
    });

final subtitlesProvider = FutureProvider.autoDispose
    .family<List<SubtitleInfo>, ({String type, String videoId})>((
      ref,
      arg,
    ) async {
      final addons = await ref.watch(loadedAddonsProvider.future);
      return ref
          .watch(moviesRepositoryProvider)
          .subtitles(addons, arg.type, arg.videoId);
    });

// ---------------------------------------------------------------------------
// Watch history & settings
// ---------------------------------------------------------------------------

final watchHistoryProvider =
    NotifierProvider<WatchHistoryNotifier, List<WatchEntry>>(
      WatchHistoryNotifier.new,
    );

class WatchHistoryNotifier extends Notifier<List<WatchEntry>> {
  static const _max = 60;

  MoviesRepository get _repo => ref.read(moviesRepositoryProvider);

  @override
  List<WatchEntry> build() =>
      _repo.getHistory()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  void record(WatchEntry entry) {
    final list = [
      entry,
      for (final e in state)
        if (e.videoId != entry.videoId) e,
    ];
    state = list.take(_max).toList();
    _repo.saveHistory(state);
  }

  void remove(String videoId) {
    state = [
      for (final e in state)
        if (e.videoId != videoId) e,
    ];
    _repo.saveHistory(state);
  }

  WatchEntry? entryFor(String videoId) =>
      state.where((e) => e.videoId == videoId).firstOrNull;
}

/// Unfinished titles, newest first, one per show.
final continueWatchingProvider = Provider<List<WatchEntry>>((ref) {
  final seen = <String>{};
  return [
    for (final e in ref.watch(watchHistoryProvider))
      if (!e.finished && seen.add(e.metaId)) e,
  ];
});

final subtitleLanguageProvider =
    NotifierProvider<SubtitleLanguageNotifier, String>(
      SubtitleLanguageNotifier.new,
    );

class SubtitleLanguageNotifier extends Notifier<String> {
  @override
  String build() => ref.read(moviesRepositoryProvider).getSubtitleLanguage();

  void set(String lang) {
    state = lang;
    ref.read(moviesRepositoryProvider).saveSubtitleLanguage(lang);
  }
}
