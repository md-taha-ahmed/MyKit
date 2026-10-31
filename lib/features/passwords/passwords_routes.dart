import 'package:go_router/go_router.dart';

import 'presentation/screens/entry_screens.dart';
import 'presentation/screens/passwords_home_screen.dart';
import 'presentation/screens/vault_settings_screen.dart';

abstract final class PasswordsRoutes {
  static const home = '/passwords';
  static const create = '/passwords/new';
  static const settings = '/passwords/settings';
  static String entry(String id) => '/passwords/entry/$id';
  static String edit(String id) => '/passwords/entry/$id/edit';

  static final routes = <RouteBase>[
    GoRoute(
      path: home,
      builder: (context, state) => const PasswordsHomeScreen(),
      routes: [
        GoRoute(
          path: 'new',
          builder: (context, state) => const EntryEditScreen(),
        ),
        GoRoute(
          path: 'settings',
          builder: (context, state) => const VaultSettingsScreen(),
        ),
        GoRoute(
          path: 'entry/:id',
          builder: (context, state) =>
              EntryScreen(entryId: state.pathParameters['id']!),
          routes: [
            GoRoute(
              path: 'edit',
              builder: (context, state) =>
                  EntryEditScreen(entryId: state.pathParameters['id']),
            ),
          ],
        ),
      ],
    ),
  ];
}
