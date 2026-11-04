import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'presentation/screens/sections_screen.dart';
import 'presentation/screens/settings_screen.dart';
import 'presentation/screens/setup_screen.dart';
import 'presentation/screens/welcome_screen.dart';

abstract final class SetupRoutes {
  static const settings = '/settings';
  static const setup = '/setup';
  static const sections = '/sections';

  /// The checklist after the welcome tour of a fresh install.
  static const firstRun = '/setup?first=1';

  /// The welcome tour (a fresh install starts here).
  static const welcome = '/welcome';

  static const accent = Color(0xFF90A4AE);

  static final routes = <RouteBase>[
    GoRoute(
      path: settings,
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: sections,
      builder: (context, state) => const SectionsScreen(),
    ),
    GoRoute(path: welcome, builder: (context, state) => const WelcomeScreen()),
    GoRoute(
      path: setup,
      builder: (context, state) =>
          SetupScreen(firstRun: state.uri.queryParameters['first'] == '1'),
    ),
  ];
}
