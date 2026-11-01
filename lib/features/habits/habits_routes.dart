import 'package:go_router/go_router.dart';

import 'presentation/screens/coach_screen.dart';
import 'presentation/screens/habit_detail_screen.dart';
import 'presentation/screens/habit_editor_screen.dart';
import 'presentation/screens/habits_home_screen.dart';
import 'presentation/screens/system_knows_screen.dart';

abstract final class HabitsRoutes {
  static const home = '/habits';
  static const create = '/habits/new';
  static const knows = '/habits/knows';
  static String detail(String id) => '/habits/quest/$id';
  static String edit(String id) => '/habits/quest/$id/edit';
  static String talk(String id) => '/habits/quest/$id/talk';

  static final routes = <RouteBase>[
    GoRoute(
      path: home,
      builder: (context, state) => const HabitsHomeScreen(),
      routes: [
        GoRoute(
          path: 'new',
          builder: (context, state) => const HabitEditorScreen(),
        ),
        GoRoute(
          path: 'knows',
          builder: (context, state) => const SystemKnowsScreen(),
        ),
        GoRoute(
          path: 'quest/:id',
          builder: (context, state) =>
              HabitDetailScreen(habitId: state.pathParameters['id']!),
          routes: [
            GoRoute(
              path: 'edit',
              builder: (context, state) =>
                  HabitEditorScreen(habitId: state.pathParameters['id']),
            ),
            GoRoute(
              path: 'talk',
              builder: (context, state) =>
                  CoachScreen(habitId: state.pathParameters['id']!),
            ),
          ],
        ),
      ],
    ),
  ];
}
