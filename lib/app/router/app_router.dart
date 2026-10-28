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
    // Safety net: map app links (mykit://countdown/<id>) to in-app paths.
    redirect: (context, state) {
      final uri = state.uri;
      if (uri.scheme != 'mykit') return null;
      return Uri(path: '/${uri.host}${uri.path}').toString();
    },
    // Never strand the user on an error page; go back to the dashboard.
    errorBuilder: (context, state) => const DashboardScreen(),
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
