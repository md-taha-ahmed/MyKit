import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import '../../core/tools/tool_definition.dart';
import 'countdown_routes.dart';
import 'presentation/providers/countdown_providers.dart';

final countdownTool = ToolDefinition(
  id: 'countdown',
  name: 'Countdown',
  description: 'Countdown rings for your home screen',
  icon: Icons.timelapse,
  color: const Color(0xFF4C8DFF),
  rootPath: CountdownRoutes.list,
  routes: CountdownRoutes.routes,
  status: (ref) {
    final n = ref.watch(countdownsProvider).length;
    return n == 0
        ? null
        : n == 1
        ? tr('1 countdown')
        : tr('{n} countdowns', {'n': n});
  },
);
