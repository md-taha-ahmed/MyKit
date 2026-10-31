import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import '../tools_registry.dart';
import 'package:flutter/material.dart';
import '../../features/backup/backup_routes.dart';
import '../../features/backup/presentation/providers/backup_providers.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../../features/setup/setup_routes.dart';

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
      for (final tool in toolsRegistry)
        ...themedRoutes(tool.routes, tool.color),
      ...themedRoutes(BackupRoutes.routes, backupAccent),
      ...themedRoutes(SetupRoutes.routes, SetupRoutes.accent),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// Wraps every screen of a tool in the app theme built around [accent], so
/// buttons, chips, switches and progress bars use the tool's colour.
List<RouteBase> themedRoutes(List<RouteBase> routes, Color accent) => [
  for (final r in routes)
    if (r is GoRoute && r.builder != null)
      GoRoute(
        path: r.path,
        name: r.name,
        redirect: r.redirect,
        parentNavigatorKey: r.parentNavigatorKey,
        builder: (context, state) => Theme(
          data: AppTheme.forAccent(accent),
          child: r.builder!(context, state),
        ),
        routes: themedRoutes(r.routes, accent),
      )
    else
      r,
];
