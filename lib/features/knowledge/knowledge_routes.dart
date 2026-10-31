import 'package:go_router/go_router.dart';

import 'presentation/screens/knowledge_home_screen.dart';
import 'presentation/screens/track_reader_screen.dart';

abstract final class KnowledgeRoutes {
  static const home = '/knowledge';
  static String read(String trackId) => '/knowledge/read/$trackId';

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
      ],
    ),
  ];
}
