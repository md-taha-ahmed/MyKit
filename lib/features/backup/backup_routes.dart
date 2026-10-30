import 'package:go_router/go_router.dart';

import 'presentation/screens/backup_screen.dart';

abstract final class BackupRoutes {
  static const home = '/backup';

  static final routes = <RouteBase>[
    GoRoute(path: home, builder: (context, state) => const BackupScreen()),
  ];
}
