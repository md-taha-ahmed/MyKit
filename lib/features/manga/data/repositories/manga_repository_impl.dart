import '../../domain/entities/manga_entities.dart';
import '../../domain/repositories/manga_repository.dart';
import '../datasources/extension_repo_remote_data_source.dart';
import '../datasources/manga_local_data_source.dart';
import '../datasources/manga_native_data_source.dart';

class MangaRepositoryImpl implements MangaRepository {
  MangaRepositoryImpl(this._local, this._remote, this._native);

  final MangaLocalDataSource _local;
  final ExtensionRepoRemoteDataSource _remote;
  final MangaNativeDataSource _native;

  @override
  List<ExtensionRepo> getRepos() => _local.readRepos();

  @override
  Future<void> saveRepos(List<ExtensionRepo> repos) => _local.writeRepos(repos);

  @override
  Future<({ExtensionRepo repo, List<AvailableExtension> extensions})> fetchRepo(
    String url,
  ) => _remote.fetch(url);

  @override
  Future<List<InstalledExtension>> installedExtensions() => _native.installed();

  @override
  Future<InstalledExtension> install(AvailableExtension extension) =>
      _native.install(extension);

  @override
  Future<void> uninstall(String pkgName) => _native.uninstall(pkgName);

  @override
  Future<MangasPage> popular(String sourceId, int page) =>
      _native.popular(sourceId, page);

  @override
  Future<MangasPage> latest(String sourceId, int page) =>
      _native.latest(sourceId, page);

  @override
  Future<MangasPage> search(String sourceId, String query, int page) =>
      _native.search(sourceId, query, page);

  @override
  Future<Manga> details(Manga manga) => _native.details(manga);

  @override
  Future<List<Chapter>> chapters(Manga manga) => _native.chapters(manga);

  @override
  Future<List<ReaderPage>> pages(String sourceId, Chapter chapter) =>
      _native.pages(sourceId, chapter);

  @override
  Future<String> pageImage(String sourceId, ReaderPage page) =>
      _native.pageImage(sourceId, page);

  @override
  Future<String> cover(String sourceId, String url) =>
      _native.cover(sourceId, url);

  @override
  Future<String?> webUrl(Manga manga, {Chapter? chapter}) =>
      _native.webUrl(manga, chapter: chapter);

  @override
  List<LibraryEntry> getLibrary() => _local.readLibrary();

  @override
  Future<void> saveLibrary(List<LibraryEntry> library) =>
      _local.writeLibrary(library);

  @override
  ({bool showNsfw, MangaReadingMode mode, Set<String> langs}) getSettings() =>
      _local.readSettings();

  @override
  Future<void> saveSettings({
    required bool showNsfw,
    required MangaReadingMode mode,
    required Set<String> langs,
  }) => _local.writeSettings(showNsfw: showNsfw, mode: mode, langs: langs);
}
