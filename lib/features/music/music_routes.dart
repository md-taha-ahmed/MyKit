import 'package:go_router/go_router.dart';

import 'presentation/screens/music_folder_screen.dart';
import 'presentation/screens/music_home_screen.dart';
import 'presentation/screens/now_playing_screen.dart';

abstract final class MusicRoutes {
  static const home = '/music';
  static const nowPlaying = '/music/now-playing';

  /// Folder paths contain slashes, so they travel as a query parameter.
  static String folder(String path) =>
      Uri(path: '/music/folder', queryParameters: {'path': path}).toString();

  static final routes = <RouteBase>[
    GoRoute(
      path: home,
      builder: (context, state) => const MusicHomeScreen(),
      routes: [
        GoRoute(
          path: 'folder',
          builder: (context, state) =>
              MusicFolderScreen(path: state.uri.queryParameters['path'] ?? ''),
        ),
        GoRoute(
          path: 'now-playing',
          builder: (context, state) => const NowPlayingScreen(),
        ),
      ],
    ),
  ];
}
