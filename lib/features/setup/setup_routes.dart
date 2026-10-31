import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'presentation/screens/settings_screen.dart';
import 'presentation/screens/setup_screen.dart';

abstract final class SetupRoutes {
  static const settings = '/settings';
  static const setup = '/setup';

  /// The checklist as the welcome screen of a fresh install.
  static const firstRun = '/setup?first=1';

  static const accent = Color(0xFF90A4AE);

  static final routes = <RouteBase>[
    GoRoute(
      path: settings,
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: setup,
      builder: (context, state) =>
          SetupScreen(firstRun: state.uri.queryParameters['first'] == '1'),
    ),
  ];
}
