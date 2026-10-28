import 'package:go_router/go_router.dart';

import 'presentation/screens/countdown_detail_screen.dart';
import 'presentation/screens/countdown_edit_screen.dart';
import 'presentation/screens/countdown_list_screen.dart';

abstract final class CountdownRoutes {
  static const list = '/countdown';
  static const create = '/countdown/new';
  static String detail(String id) => '/countdown/$id';
  static String edit(String id) => '/countdown/$id/edit';

  static final routes = <RouteBase>[
    GoRoute(
      path: list,
      builder: (context, state) => const CountdownListScreen(),
      routes: [
        // Declared before ':id' so "new" isn't treated as an id.
        GoRoute(
          path: 'new',
          builder: (context, state) => const CountdownEditScreen(),
        ),
        GoRoute(
          path: ':id',
          builder: (context, state) =>
              CountdownDetailScreen(countdownId: state.pathParameters['id']!),
          routes: [
            GoRoute(
              path: 'edit',
              builder: (context, state) =>
                  CountdownEditScreen(countdownId: state.pathParameters['id']),
            ),
          ],
        ),
      ],
    ),
  ];
}
