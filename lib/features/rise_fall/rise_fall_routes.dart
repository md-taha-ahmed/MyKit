import 'package:go_router/go_router.dart';

import 'presentation/screens/country_screen.dart';
import 'presentation/screens/part_reader_screen.dart';
import 'presentation/screens/patterns_screens.dart';
import 'presentation/screens/rise_fall_home_screen.dart';

abstract final class RiseFallRoutes {
  static const home = '/rise-fall';
  static const patterns = '/rise-fall/patterns';
  static const compare = '/rise-fall/compare';
  static String country(String id) => '/rise-fall/country/$id';
  static String part(String id, int part) => '/rise-fall/country/$id/$part';
  static String pattern(String name) => '/rise-fall/patterns/$name';

  static final routes = <RouteBase>[
    GoRoute(
      path: home,
      builder: (context, state) => const RiseFallHomeScreen(),
      routes: [
        GoRoute(
          path: 'patterns',
          builder: (context, state) => const PatternsScreen(),
          routes: [
            GoRoute(
              path: ':name',
              builder: (context, state) =>
                  PatternScreen(name: state.pathParameters['name']!),
            ),
          ],
        ),
        GoRoute(
          path: 'compare',
          builder: (context, state) => const CompareScreen(),
        ),
        GoRoute(
          path: 'country/:id',
          builder: (context, state) =>
              CountryScreen(id: state.pathParameters['id']!),
          routes: [
            GoRoute(
              path: ':part',
              builder: (context, state) => PartReaderScreen(
                id: state.pathParameters['id']!,
                part: int.parse(state.pathParameters['part']!),
              ),
            ),
          ],
        ),
      ],
    ),
  ];
}
