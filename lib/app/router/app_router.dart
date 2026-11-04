import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import '../tools_registry.dart';
import 'package:flutter/material.dart';
import '../../core/tools/tool_switch.dart';
import '../../features/backup/backup_routes.dart';
import '../../features/backup/presentation/providers/backup_providers.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../../features/setup/presentation/widgets/tool_tips.dart';
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
      if (uri.scheme == 'mykit') {
        return Uri(path: '/${uri.host}${uri.path}').toString();
      }
      // A turned-off tool can't be opened, even from a widget or a link.
      final off = ref.read(disabledToolsProvider);
      return ToolSwitch.blocks(uri.path, toolsRegistry, off)
          ? AppRoutes.dashboard
          : null;
    },
    // Never strand the user on an error page; go back to the dashboard.
    errorBuilder: (context, state) => const DashboardScreen(),
    routes: [
      GoRoute(
        path: AppRoutes.dashboard,
        builder: (context, state) => const DashboardScreen(),
      ),
      for (final tool in toolsRegistry)
        ...themedRoutes(
          tool.routes,
          tool.color,
          tips: (path: tool.rootPath, toolId: tool.id),
        ),
      ...themedRoutes(BackupRoutes.routes, backupAccent),
      ...themedRoutes(SetupRoutes.routes, SetupRoutes.accent),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// Wraps every screen of a tool in the app theme built around [accent], so
/// buttons, chips, switches and progress bars use the tool's colour.
///
/// With [tips], the screen at `tips.path` shows the tool's quick tips the
/// first time it opens.
List<RouteBase> themedRoutes(
  List<RouteBase> routes,
  Color accent, {
  ({String path, String toolId})? tips,
}) => [
  for (final r in routes)
    if (r is GoRoute && r.builder != null)
      GoRoute(
        path: r.path,
        name: r.name,
        redirect: r.redirect,
        parentNavigatorKey: r.parentNavigatorKey,
        builder: (context, state) {
          final screen = Theme(
            data: AppTheme.forAccent(accent),
            child: r.builder!(context, state),
          );
          return tips != null && r.path == tips.path
              ? ToolTipsGate(toolId: tips.toolId, child: screen)
              : screen;
        },
        routes: themedRoutes(r.routes, accent),
      )
    else
      r,
];
