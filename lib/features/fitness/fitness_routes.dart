import 'package:go_router/go_router.dart';

import 'presentation/screens/exercise_detail_screen.dart';
import 'presentation/screens/exercise_list_screen.dart';
import 'presentation/screens/fitness_home_screen.dart';
import 'presentation/screens/routine_edit_screen.dart';
import 'presentation/screens/workout_screen.dart';

abstract final class FitnessRoutes {
  static const home = '/fitness';
  static const workout = '/fitness/workout';

  /// Pick an exercise; the route pops with its id.
  static const pickExercise = '/fitness/pick';

  static String exercise(String id) =>
      Uri(path: '/fitness/exercise', queryParameters: {'id': id}).toString();

  static String routine(String id) => '/fitness/routine/$id';

  static final routes = <RouteBase>[
    GoRoute(
      path: home,
      builder: (context, state) => const FitnessHomeScreen(),
      routes: [
        GoRoute(
          path: 'exercise',
          builder: (context, state) => ExerciseDetailScreen(
            exerciseId: state.uri.queryParameters['id'] ?? '',
          ),
        ),
        GoRoute(
          path: 'routine/:id',
          builder: (context, state) =>
              RoutineEditScreen(routineId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: 'workout',
          builder: (context, state) => const WorkoutScreen(),
        ),
        GoRoute(
          path: 'pick',
          builder: (context, state) => const ExerciseListScreen(picker: true),
        ),
      ],
    ),
  ];
}
