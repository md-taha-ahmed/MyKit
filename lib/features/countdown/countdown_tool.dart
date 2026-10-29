import 'package:flutter/material.dart';

import '../../core/tools/tool_definition.dart';
import 'countdown_routes.dart';
import 'presentation/providers/countdown_providers.dart';

final countdownTool = ToolDefinition(
  id: 'countdown',
  name: 'Countdown',
  description: 'Countdown rings for your home screen',
  icon: Icons.timelapse,
  color: const Color(0xFF7B1FA2),
  rootPath: CountdownRoutes.list,
  routes: CountdownRoutes.routes,
  status: (ref) {
    final n = ref.watch(countdownsProvider).length;
    return n == 0 ? null : '$n ${n == 1 ? 'countdown' : 'countdowns'}';
  },
);
