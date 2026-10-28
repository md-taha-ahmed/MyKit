import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../tools_registry.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';

abstract final class AppRoutes {
  static const dashboard = '/';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.dashboard,
    routes: [
      GoRoute(
        path: AppRoutes.dashboard,
        builder: (context, state) => const DashboardScreen(),
      ),
      for (final tool in toolsRegistry) ...tool.routes,
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
