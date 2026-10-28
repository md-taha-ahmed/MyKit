import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../../core/storage/shared_preferences_provider.dart';
import '../../data/datasources/extension_repo_remote_data_source.dart';
import '../../data/datasources/manga_local_data_source.dart';
import '../../data/datasources/manga_native_data_source.dart';
import '../../data/repositories/manga_repository_impl.dart';
import '../../domain/entities/manga_entities.dart';
import '../../domain/repositories/manga_repository.dart';

/// Default repository suggested in the UI (keiyoushi, as in the request).
const keiyoushiRepoUrl =
    'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json';

// ---------------------------------------------------------------------------
// Dependencies
// ---------------------------------------------------------------------------

final mangaRepositoryProvider = Provider<MangaRepository>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return MangaRepositoryImpl(
    MangaLocalDataSource(ref.watch(sharedPreferencesProvider)),
    ExtensionRepoRemoteDataSource(client),
    MangaNativeDataSource(),
  );
});

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

typedef MangaSettings = ({
  bool showNsfw,
  MangaReadingMode mode,
  Set<String> langs,
});

final mangaSettingsProvider =
    NotifierProvider<MangaSettingsNotifier, MangaSettings>(
      MangaSettingsNotifier.new,
    );

class MangaSettingsNotifier extends Notifier<MangaSettings> {
  @override
  MangaSettings build() => ref.read(mangaRepositoryProvider).getSettings();

  void _save(MangaSettings s) {
    state = s;
    ref
        .read(mangaRepositoryProvider)
        .saveSettings(showNsfw: s.showNsfw, mode: s.mode, langs: s.langs);
  }

  void setShowNsfw(bool v) =>
      _save((showNsfw: v, mode: state.mode, langs: state.langs));

  void setMode(MangaReadingMode m) =>
      _save((showNsfw: state.showNsfw, mode: m, langs: state.langs));

  void toggleLang(String lang) {
    final langs = {...state.langs};
    langs.contains(lang) ? langs.remove(lang) : langs.add(lang);
    _save((showNsfw: state.showNsfw, mode: state.mode, langs: langs));
  }
}

// ---------------------------------------------------------------------------
// Repositories & extensions
// ---------------------------------------------------------------------------

final extensionReposProvider =
    NotifierProvider<ExtensionReposNotifier, List<ExtensionRepo>>(
      ExtensionReposNotifier.new,
    );

class ExtensionReposNotifier extends Notifier<List<ExtensionRepo>> {
  MangaRepository get _repo => ref.read(mangaRepositoryProvider);

  @override
  List<ExtensionRepo> build() => _repo.getRepos();

  /// Resolves and validates [url]; throws [MangaException] if it isn't a repo.
  Future<ExtensionRepo> add(String url) async {
    final fetched = await _repo.fetchRepo(url);
    final repos = [
      ...state.where((r) => r.signingKey != fetched.repo.signingKey),
      fetched.repo,
    ];
    state = repos;
    await _repo.saveRepos(repos);
    ref.invalidate(availableExtensionsProvider);
    return fetched.repo;
  }

  Future<void> remove(String url) async {
    state = state.where((r) => r.url != url).toList();
    await _repo.saveRepos(state);
    ref.invalidate(availableExtensionsProvider);
  }
}

/// Every extension listed by the user's repositories.
final availableExtensionsProvider = FutureProvider<List<AvailableExtension>>((
  ref,
) async {
  final repos = ref.watch(extensionReposProvider);
  final repo = ref.read(mangaRepositoryProvider);
  final lists = await Future.wait(
    repos.map((r) async => (await repo.fetchRepo(r.url)).extensions),
  );
  final all = [for (final l in lists) ...l];
  all.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return all;
});

final installedExtensionsProvider =
    AsyncNotifierProvider<
      InstalledExtensionsNotifier,
      List<InstalledExtension>
    >(InstalledExtensionsNotifier.new);

class InstalledExtensionsNotifier
    extends AsyncNotifier<List<InstalledExtension>> {
  MangaRepository get _repo => ref.read(mangaRepositoryProvider);

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

/// Package names currently downloading/installing.
final installingProvider = NotifierProvider<InstallingNotifier, Set<String>>(
  InstallingNotifier.new,
);

class InstallingNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void set(String pkg, bool busy) =>
      state = busy ? {...state, pkg} : ({...state}..remove(pkg));
}

/// Installed sources the user wants to see (language + NSFW filters).
final visibleSourcesProvider = Provider<AsyncValue<List<MangaSource>>>((ref) {
  final settings = ref.watch(mangaSettingsProvider);
  return ref.watch(installedExtensionsProvider).whenData((exts) {
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

final mangaSourceProvider = Provider.family<MangaSource?, String>((ref, id) {
  for (final e in ref.watch(installedExtensionsProvider).value ?? const []) {
    for (final s in e.sources) {
      if (s.id == id) return s;
    }
  }
  return null;
});

// ---------------------------------------------------------------------------
// Manga cache (shared by browse → details → reader)
// ---------------------------------------------------------------------------

final mangaCacheProvider =
    NotifierProvider<MangaCacheNotifier, Map<String, Manga>>(
      MangaCacheNotifier.new,
    );

class MangaCacheNotifier extends Notifier<Map<String, Manga>> {
  @override
  Map<String, Manga> build() => {
    for (final e in ref.read(mangaRepositoryProvider).getLibrary())
      e.manga.key: e.manga,
  };

  void put(Manga m) => state = {...state, m.key: m};

  void putAll(Iterable<Manga> ms) =>
      state = {...state, for (final m in ms) m.key: m};
}

/// Full details for a cached manga (refreshes the cache and library copy).
final mangaDetailsProvider = FutureProvider.autoDispose.family<Manga, String>((
  ref,
  key,
) async {
  final cached = ref.read(mangaCacheProvider)[key];
  if (cached == null) throw const MangaException('Manga not found');
  final fresh = cached.merge(
    await ref.read(mangaRepositoryProvider).details(cached),
  );
  ref.read(mangaCacheProvider.notifier).put(fresh);
  ref.read(mangaLibraryProvider.notifier).updateManga(fresh);
  return fresh;
});

/// Chapters, newest first as sources return them. Kept alive for the reader.
final chaptersProvider = FutureProvider.family<List<Chapter>, String>((
  ref,
  key,
) async {
  final manga = ref.read(mangaCacheProvider)[key];
  if (manga == null) throw const MangaException('Manga not found');
  return ref.read(mangaRepositoryProvider).chapters(manga);
});

typedef CoverRequest = ({String sourceId, String url});

final coverFileProvider = FutureProvider.autoDispose
    .family<String, CoverRequest>((ref, req) {
      ref.keepAlive();
      return ref.read(mangaRepositoryProvider).cover(req.sourceId, req.url);
    });

typedef ChapterRef = ({String mangaKey, String chapterUrl});

final chapterPagesProvider = FutureProvider.autoDispose
    .family<List<ReaderPage>, ChapterRef>((ref, c) async {
      final manga = ref.read(mangaCacheProvider)[c.mangaKey]!;
      final chapters = await ref.read(chaptersProvider(c.mangaKey).future);
      final chapter = chapters.firstWhere((ch) => ch.url == c.chapterUrl);
      return ref.read(mangaRepositoryProvider).pages(manga.sourceId, chapter);
    });

typedef PageRef = ({String sourceId, ReaderPage page});

/// Downloaded page file. Kept alive (just a path) so prefetching sticks.
final pageImageProvider = FutureProvider.autoDispose.family<String, PageRef>((
  ref,
  p,
) async {
  final path = await ref
      .read(mangaRepositoryProvider)
      .pageImage(p.sourceId, p.page);
  ref.keepAlive();
  return path;
});

// ---------------------------------------------------------------------------
// Library
// ---------------------------------------------------------------------------

final mangaLibraryProvider =
    NotifierProvider<MangaLibraryNotifier, List<LibraryEntry>>(
      MangaLibraryNotifier.new,
    );

class MangaLibraryNotifier extends Notifier<List<LibraryEntry>> {
  MangaRepository get _repo => ref.read(mangaRepositoryProvider);

  @override
  List<LibraryEntry> build() => _repo.getLibrary();

  Future<void> _set(List<LibraryEntry> v) async {
    state = v;
    await _repo.saveLibrary(v);
  }

  LibraryEntry? entry(String key) {
    for (final e in state) {
      if (e.manga.key == key) return e;
    }
    return null;
  }

  Future<void> toggle(Manga manga) => entry(manga.key) != null
      ? _set(state.where((e) => e.manga.key != manga.key).toList())
      : _set([...state, LibraryEntry(manga: manga, addedAt: DateTime.now())]);

  Future<void> updateManga(Manga manga) async {
    if (entry(manga.key) == null) return;
    await _set([
      for (final e in state)
        e.manga.key == manga.key ? e.copyWith(manga: manga) : e,
    ]);
  }

  /// Saves the reading position; finishing a chapter marks it read.
  Future<void> saveProgress(
    Manga manga,
    String chapterUrl,
    int page, {
    bool finished = false,
  }) async {
    var e = entry(manga.key);
    if (e == null) {
      // Track progress even for titles not in the library yet.
      e = LibraryEntry(manga: manga, addedAt: DateTime.now());
      _history[manga.key] = e;
    }
    final updated = e.copyWith(
      lastChapterUrl: chapterUrl,
      lastPage: page,
      lastReadAt: DateTime.now(),
      readChapters: finished ? {...e.readChapters, chapterUrl} : null,
    );
    if (entry(manga.key) != null) {
      await _set([
        for (final x in state) x.manga.key == manga.key ? updated : x,
      ]);
    } else {
      _history[manga.key] = updated;
    }
  }

  Future<void> setRead(Manga manga, String chapterUrl, bool read) async {
    final e = entry(manga.key);
    if (e == null) return;
    final chapters = {...e.readChapters};
    read ? chapters.add(chapterUrl) : chapters.remove(chapterUrl);
    await _set([
      for (final x in state)
        x.manga.key == manga.key ? x.copyWith(readChapters: chapters) : x,
    ]);
  }

  /// In-memory progress for titles outside the library (this session only).
  final Map<String, LibraryEntry> _history = {};

  LibraryEntry? progressFor(String key) => entry(key) ?? _history[key];
}
