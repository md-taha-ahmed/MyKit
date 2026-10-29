import 'package:go_router/go_router.dart';

import 'presentation/screens/anime_details_screen.dart';
import 'presentation/screens/anime_source_browse_screen.dart';
import 'presentation/screens/manga_details_screen.dart';
import 'presentation/screens/manga_home_screen.dart';
import 'presentation/screens/manga_reader_screen.dart';
import 'presentation/screens/source_browse_screen.dart';

abstract final class MangaRoutes {
  static const home = '/manga';

  static String source(String sourceId, {bool latest = false}) =>
      '/manga/source/$sourceId${latest ? '?latest=1' : ''}';

  /// Manga keys contain URLs, so they travel as query parameters.
  static String details(String mangaKey) =>
      Uri(path: '/manga/title', queryParameters: {'key': mangaKey}).toString();

  static String reader(String mangaKey, String chapterUrl) => Uri(
    path: '/manga/read',
    queryParameters: {'key': mangaKey, 'chapter': chapterUrl},
  ).toString();

  static String animeSource(String sourceId, {bool latest = false}) =>
      '/manga/anime/source/$sourceId${latest ? '?latest=1' : ''}';

  /// Anime keys contain URLs, so they travel as query parameters.
  static String animeDetails(String animeKey) => Uri(
    path: '/manga/anime/title',
    queryParameters: {'key': animeKey},
  ).toString();

  static final routes = <RouteBase>[
    GoRoute(
      path: home,
      builder: (context, state) => const MangaHomeScreen(),
      routes: [
        GoRoute(
          path: 'source/:sourceId',
          builder: (context, state) => SourceBrowseScreen(
            sourceId: state.pathParameters['sourceId']!,
            startWithLatest: state.uri.queryParameters['latest'] == '1',
          ),
        ),
        GoRoute(
          path: 'title',
          builder: (context, state) =>
              MangaDetailsScreen(mangaKey: state.uri.queryParameters['key']!),
        ),
        GoRoute(
          path: 'anime/source/:sourceId',
          builder: (context, state) => AnimeSourceBrowseScreen(
            sourceId: state.pathParameters['sourceId']!,
            startWithLatest: state.uri.queryParameters['latest'] == '1',
          ),
        ),
        GoRoute(
          path: 'anime/title',
          builder: (context, state) =>
              AnimeDetailsScreen(animeKey: state.uri.queryParameters['key']!),
        ),
        GoRoute(
          path: 'read',
          builder: (context, state) => MangaReaderScreen(
            mangaKey: state.uri.queryParameters['key']!,
            chapterUrl: state.uri.queryParameters['chapter']!,
          ),
        ),
      ],
    ),
  ];
}
