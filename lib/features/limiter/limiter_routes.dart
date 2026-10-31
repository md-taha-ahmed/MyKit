import 'package:go_router/go_router.dart';

import 'presentation/screens/limiter_home_screen.dart';

abstract final class LimiterRoutes {
  static const home = '/screen-time';

  static final routes = <RouteBase>[
    GoRoute(path: home, builder: (context, state) => const LimiterHomeScreen()),
  ];
}
