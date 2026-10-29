import 'package:flutter/material.dart';

import '../../core/tools/tool_definition.dart';
import 'fitness_routes.dart';
import 'presentation/providers/fitness_providers.dart';

final fitnessTool = ToolDefinition(
  id: 'fitness',
  name: 'Fitness',
  description: 'Home workouts, exercise library and progress',
  icon: Icons.fitness_center,
  color: fitnessAccent,
  rootPath: FitnessRoutes.home,
  routes: FitnessRoutes.routes,
  status: (ref) {
    if (ref.watch(activeWorkoutProvider) != null) return 'Workout in progress';
    final next = ref.watch(nextRoutineProvider);
    if (next == null) return null;
    return switch (next.inDays) {
      0 => '${next.routine.name} today',
      1 => '${next.routine.name} tomorrow',
      _ => 'Next: ${next.routine.name}',
    };
  },
);
