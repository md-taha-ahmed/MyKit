import 'package:go_router/go_router.dart';

import 'presentation/screens/addons_screen.dart';
import 'presentation/screens/catalog_screen.dart';
import 'presentation/screens/movies_home_screen.dart';
import 'presentation/screens/movies_search_screen.dart';
import 'presentation/screens/player_screen.dart';
import 'presentation/screens/streams_screen.dart';
import 'presentation/screens/title_details_screen.dart';

abstract final class MoviesRoutes {
  static const home = '/movies';
  static const addons = '/movies/addons';
  static const search = '/movies/search';

  static String catalog(String addonUrl, String type, String id, String name) =>
      Uri(
        path: '/movies/catalog',
        queryParameters: {
          'addon': addonUrl,
          'type': type,
          'id': id,
          'name': name,
        },
      ).toString();

  static String title(String type, String id) => Uri(
    path: '/movies/title',
    queryParameters: {'type': type, 'id': id},
  ).toString();

  /// Sources for [videoId] (the movie id, or `tt…:season:episode`).
  static String streams(String type, String metaId, String videoId) => Uri(
    path: '/movies/streams',
    queryParameters: {'type': type, 'id': metaId, 'video': videoId},
  ).toString();

  /// Takes a [PlayerArgs] as `extra`.
  static const play = '/movies/play';

  static final routes = <RouteBase>[
    GoRoute(
      path: home,
      builder: (context, state) => const MoviesHomeScreen(),
      routes: [
        GoRoute(
          path: 'addons',
          builder: (context, state) => const AddonsScreen(),
        ),
        GoRoute(
          path: 'search',
          builder: (context, state) => const MoviesSearchScreen(),
        ),
        GoRoute(
          path: 'catalog',
          builder: (context, state) {
            final q = state.uri.queryParameters;
            return CatalogScreen(
              addonUrl: q['addon']!,
              type: q['type']!,
              id: q['id']!,
              name: q['name'] ?? '',
            );
          },
        ),
        GoRoute(
          path: 'title',
          builder: (context, state) => TitleDetailsScreen(
            type: state.uri.queryParameters['type']!,
            id: state.uri.queryParameters['id']!,
          ),
        ),
        GoRoute(
          path: 'streams',
          builder: (context, state) {
            final q = state.uri.queryParameters;
            return StreamsScreen(
              type: q['type']!,
              metaId: q['id']!,
              videoId: q['video']!,
            );
          },
        ),
        GoRoute(
          path: 'play',
          builder: (context, state) {
            final args = state.extra;
            return args is PlayerArgs
                ? PlayerScreen(args: args)
                : const MoviesHomeScreen();
          },
        ),
      ],
    ),
  ];
}
