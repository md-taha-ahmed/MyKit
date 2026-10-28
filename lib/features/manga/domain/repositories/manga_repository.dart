import '../entities/manga_entities.dart';

class MangaException implements Exception {
  const MangaException(this.message, {this.details});

  final String message;
  final String? details;

  @override
  String toString() => message;
}

abstract interface class MangaRepository {
  // Repositories & extensions
  List<ExtensionRepo> getRepos();
  Future<void> saveRepos(List<ExtensionRepo> repos);
  Future<({ExtensionRepo repo, List<AvailableExtension> extensions})> fetchRepo(
    String url,
  );
  Future<List<InstalledExtension>> installedExtensions();
  Future<InstalledExtension> install(AvailableExtension extension);
  Future<void> uninstall(String pkgName);

  // Browsing
  Future<MangasPage> popular(String sourceId, int page);
  Future<MangasPage> latest(String sourceId, int page);
  Future<MangasPage> search(String sourceId, String query, int page);
  Future<Manga> details(Manga manga);
  Future<List<Chapter>> chapters(Manga manga);
  Future<List<ReaderPage>> pages(String sourceId, Chapter chapter);
  Future<String> pageImage(String sourceId, ReaderPage page);
  Future<String> cover(String sourceId, String url);
  Future<String?> webUrl(Manga manga, {Chapter? chapter});

  // Library & settings
  List<LibraryEntry> getLibrary();
  Future<void> saveLibrary(List<LibraryEntry> library);
  ({bool showNsfw, MangaReadingMode mode, Set<String> langs}) getSettings();
  Future<void> saveSettings({
    required bool showNsfw,
    required MangaReadingMode mode,
    required Set<String> langs,
  });
}
