import 'package:go_router/go_router.dart';

import 'domain/sahaba_models.dart';
import 'presentation/screens/knowledge_home_screen.dart';
import 'presentation/screens/sahaba_screens.dart';
import 'presentation/screens/track_reader_screen.dart';

abstract final class KnowledgeRoutes {
  static const home = '/knowledge';
  static String read(String trackId) => '/knowledge/read/$trackId';
  static const sahaba = '/knowledge/sahaba';
  static String sahabaPerson(String id) => '/knowledge/sahaba/$id';
  static String sahabaChapter(String id, String book, String index) =>
      '/knowledge/sahaba/$id/$book/$index';

  static final routes = <RouteBase>[
    GoRoute(
      path: home,
      builder: (context, state) => const KnowledgeHomeScreen(),
      routes: [
        GoRoute(
          path: 'read/:track',
          builder: (context, state) =>
              TrackReaderScreen(trackId: state.pathParameters['track']!),
        ),
        GoRoute(
          path: 'sahaba',
          builder: (context, state) => const SahabaHomeScreen(),
          routes: [
            GoRoute(
              path: ':id',
              builder: (context, state) =>
                  SahabaPersonScreen(id: state.pathParameters['id']!),
              routes: [
                GoRoute(
                  path: ':book/:index',
                  builder: (context, state) => SahabaReaderScreen(
                    // Replacing one chapter with the next must start fresh.
                    key: state.pageKey,
                    id: state.pathParameters['id']!,
                    book: SahabaBook.values.byName(
                      state.pathParameters['book']!,
                    ),
                    index: int.parse(state.pathParameters['index']!),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ];
}
