import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/shared_preferences_provider.dart';
import '../../data/datasources/anime_native_data_source.dart';
import '../../data/repositories/anime_repository_impl.dart';
import '../../domain/entities/anime_entities.dart';
import '../../domain/entities/manga_entities.dart';
import '../../domain/repositories/anime_repository.dart';
import '../../domain/repositories/manga_repository.dart';
import 'manga_providers.dart';

/// A ready-made anime repository suggested in the UI.
const yuzonoAnimeRepoUrl =
    'https://raw.githubusercontent.com/yuzono/anime-repo/repo/index.min.json';

final animeRepositoryProvider = Provider<AnimeRepository>(
  (ref) => AnimeRepositoryImpl(
    ref.watch(sharedPreferencesProvider),
    AnimeNativeDataSource(),
  ),
);

// ---------------------------------------------------------------------------
// Manga | Anime switch
// ---------------------------------------------------------------------------

enum MediaMode { manga, anime }

final mediaModeProvider = NotifierProvider<MediaModeNotifier, MediaMode>(
  MediaModeNotifier.new,
);

class MediaModeNotifier extends Notifier<MediaMode> {
  static const _key = 'manga.mode';

  @override
  MediaMode build() =>
      ref.read(sharedPreferencesProvider).getString(_key) == 'anime'
      ? MediaMode.anime
      : MediaMode.manga;

  void set(MediaMode mode) {
    state = mode;
    ref.read(sharedPreferencesProvider).setString(_key, mode.name);
  }
}

// ---------------------------------------------------------------------------
// Extensions (repositories are shared with manga)
// ---------------------------------------------------------------------------

/// Anime extensions listed by the user's repositories.
final availableAnimeExtensionsProvider =
    FutureProvider<List<AvailableExtension>>((ref) async {
      final all = await ref.watch(allAvailableExtensionsProvider.future);
      return all.where((e) => e.isAnime).toList();
    });

final installedAnimeExtensionsProvider =
    AsyncNotifierProvider<
      InstalledAnimeExtensionsNotifier,
      List<InstalledExtension>
    >(InstalledAnimeExtensionsNotifier.new);

class InstalledAnimeExtensionsNotifier
    extends AsyncNotifier<List<InstalledExtension>> {
  AnimeRepository get _repo => ref.read(animeRepositoryProvider);

  @override
  Future<List<InstalledExtension>> build() => _repo.installedExtensions();

  Future<void> install(AvailableExtension ext) async {
    ref.read(installingProvider.notifier).set(ext.pkgName, true);
    try {
      await _repo.install(ext);
      state = AsyncData(await _repo.installedExtensions());
    } finally {
      ref.read(installingProvider.notifier).set(ext.pkgName, false);
    }
  }

  Future<void> uninstall(String pkgName) async {
    await _repo.uninstall(pkgName);
    state = AsyncData(await _repo.installedExtensions());
  }
}

/// Installed anime sources the user wants to see (language + NSFW filters).
final visibleAnimeSourcesProvider = Provider<AsyncValue<List<MangaSource>>>((
  ref,
) {
  final settings = ref.watch(mangaSettingsProvider);
  return ref.watch(installedAnimeExtensionsProvider).whenData((exts) {
    final sources = [
      for (final e in exts)
        for (final s in e.sources)
          if ((settings.showNsfw || !s.nsfw) &&
              (settings.langs.isEmpty ||
                  settings.langs.contains(s.lang) ||
                  s.lang == 'all'))
            s,
    ];
    sources.sort((a, b) {
      final c = a.lang.compareTo(b.lang);
      return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return sources;
  });
});

final animeSourceProvider = Provider.family<MangaSource?, String>((ref, id) {
  for (final e
      in ref.watch(installedAnimeExtensionsProvider).value ?? const []) {
    for (final s in e.sources) {
      if (s.id == id) return s;
    }
  }
  return null;
});

// ---------------------------------------------------------------------------
// Anime cache (browse → details → episodes)
// ---------------------------------------------------------------------------

final animeCacheProvider =
    NotifierProvider<AnimeCacheNotifier, Map<String, Anime>>(
      AnimeCacheNotifier.new,
    );

class AnimeCacheNotifier extends Notifier<Map<String, Anime>> {
  @override
  Map<String, Anime> build() => {
    for (final e in ref.read(animeRepositoryProvider).getLibrary())
      e.anime.key: e.anime,
  };

  void put(Anime a) => state = {...state, a.key: a};

  void putAll(Iterable<Anime> as) =>
      state = {...state, for (final a in as) a.key: a};
}

/// Full details for a cached anime (refreshes the cache and library copy).
final animeDetailsProvider = FutureProvider.autoDispose.family<Anime, String>((
  ref,
  key,
) async {
  final cached = ref.read(animeCacheProvider)[key];
  if (cached == null) throw const MangaException('Anime not found');
  final fresh = cached.merge(
    await ref.read(animeRepositoryProvider).details(cached),
  );
  ref.read(animeCacheProvider.notifier).put(fresh);
  ref.read(animeLibraryProvider.notifier).updateAnime(fresh);
  return fresh;
});

/// Episodes (or, for season-based titles, nothing — see [animeSeasonsProvider]).
final animeEpisodesProvider = FutureProvider.autoDispose
    .family<List<AnimeEpisode>, String>((ref, key) async {
      final anime = ref.read(animeCacheProvider)[key];
      if (anime == null) throw const MangaException('Anime not found');
      final episodes = await ref.read(animeRepositoryProvider).episodes(anime);
      ref.keepAlive();
      return episodes;
    });

final animeSeasonsProvider = FutureProvider.autoDispose
    .family<List<Anime>, String>((ref, key) async {
      final anime = ref.read(animeCacheProvider)[key];
      if (anime == null) throw const MangaException('Anime not found');
      final seasons = await ref.read(animeRepositoryProvider).seasons(anime);
      ref.read(animeCacheProvider.notifier).putAll(seasons);
      return seasons;
    });

final animeCoverFileProvider = FutureProvider.autoDispose
    .family<String, CoverRequest>((ref, req) {
      ref.keepAlive();
      return ref.read(animeRepositoryProvider).cover(req.sourceId, req.url);
    });

// ---------------------------------------------------------------------------
// Library
// ---------------------------------------------------------------------------

final animeLibraryProvider =
    NotifierProvider<AnimeLibraryNotifier, List<AnimeLibraryEntry>>(
      AnimeLibraryNotifier.new,
    );

class AnimeLibraryNotifier extends Notifier<List<AnimeLibraryEntry>> {
  AnimeRepository get _repo => ref.read(animeRepositoryProvider);

  /// Watch progress for titles outside the library (this session only).
  final Map<String, AnimeLibraryEntry> _history = {};

  @override
  List<AnimeLibraryEntry> build() => _repo.getLibrary();

  Future<void> _set(List<AnimeLibraryEntry> v) async {
    state = v;
    await _repo.saveLibrary(v);
  }

  AnimeLibraryEntry? entry(String key) {
    for (final e in state) {
      if (e.anime.key == key) return e;
    }
    return null;
  }

  AnimeLibraryEntry? progressFor(String key) => entry(key) ?? _history[key];

  Future<void> toggle(Anime anime) => entry(anime.key) != null
      ? _set(state.where((e) => e.anime.key != anime.key).toList())
      : _set([
          ...state,
          AnimeLibraryEntry(
            anime: anime,
            addedAt: DateTime.now(),
            watchedEpisodes: _history[anime.key]?.watchedEpisodes ?? const {},
            lastEpisodeUrl: _history[anime.key]?.lastEpisodeUrl,
            lastWatchedAt: _history[anime.key]?.lastWatchedAt,
          ),
        ]);

  Future<void> updateAnime(Anime anime) async {
    if (entry(anime.key) == null) return;
    await _set([
      for (final e in state)
        e.anime.key == anime.key ? e.copyWith(anime: anime) : e,
    ]);
  }

  /// Remembers the last episode opened; [watched] marks it as seen.
  Future<void> recordEpisode(
    Anime anime,
    String episodeUrl, {
    bool watched = false,
  }) async {
    final current =
        progressFor(anime.key) ??
        AnimeLibraryEntry(anime: anime, addedAt: DateTime.now());
    final updated = current.copyWith(
      lastEpisodeUrl: episodeUrl,
      lastWatchedAt: DateTime.now(),
      watchedEpisodes: watched
          ? {...current.watchedEpisodes, episodeUrl}
          : null,
    );
    if (entry(anime.key) != null) {
      await _set([
        for (final x in state) x.anime.key == anime.key ? updated : x,
      ]);
    } else {
      _history[anime.key] = updated;
      ref.notifyListeners();
    }
  }

  Future<void> setWatched(Anime anime, String episodeUrl, bool watched) async {
    final current = progressFor(anime.key);
    if (current == null && !watched) return;
    final base =
        current ?? AnimeLibraryEntry(anime: anime, addedAt: DateTime.now());
    final set = {...base.watchedEpisodes};
    watched ? set.add(episodeUrl) : set.remove(episodeUrl);
    final updated = base.copyWith(watchedEpisodes: set);
    if (entry(anime.key) != null) {
      await _set([
        for (final x in state) x.anime.key == anime.key ? updated : x,
      ]);
    } else {
      _history[anime.key] = updated;
      ref.notifyListeners();
    }
  }
}
