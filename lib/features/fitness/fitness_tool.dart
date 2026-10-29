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
);
