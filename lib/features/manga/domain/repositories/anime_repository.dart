import '../entities/anime_entities.dart';
import '../entities/manga_entities.dart';

/// Aniyomi anime extensions. Repositories are shared with manga
/// ([MangaRepository]); an anime repo's extensions show up here.
abstract interface class AnimeRepository {
  // Extensions
  Future<List<InstalledExtension>> installedExtensions();
  Future<InstalledExtension> install(AvailableExtension extension);
  Future<void> uninstall(String pkgName);

  // Browsing
  Future<AnimesPage> popular(String sourceId, int page);
  Future<AnimesPage> latest(String sourceId, int page);
  Future<AnimesPage> search(String sourceId, String query, int page);
  Future<Anime> details(Anime anime);
  Future<List<AnimeEpisode>> episodes(Anime anime);
  Future<List<Anime>> seasons(Anime anime);
  Future<String> cover(String sourceId, String url);
  Future<String?> webUrl(Anime anime, {AnimeEpisode? episode});

  // Playback
  Future<List<AnimeHoster>> hosters(String sourceId, AnimeEpisode episode);
  Future<List<AnimeVideo>> hosterVideos(String sourceId, String hoster);
  Future<ResolvedVideo> resolve(String sourceId, String video);

  // Library
  List<AnimeLibraryEntry> getLibrary();
  Future<void> saveLibrary(List<AnimeLibraryEntry> library);
}
