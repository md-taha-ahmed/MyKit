import 'package:flutter/material.dart';

import '../../core/tools/tool_definition.dart';
import 'limiter_routes.dart';
import 'presentation/providers/limiter_providers.dart';

final limiterTool = ToolDefinition(
  id: 'screen-time',
  name: 'Screen time',
  description: 'Daily limits for Instagram, Facebook, X and YouTube',
  icon: Icons.hourglass_bottom,
  color: limiterAccent,
  rootPath: LimiterRoutes.home,
  routes: LimiterRoutes.routes,
  status: (ref) {
    final status = ref.watch(limiterStatusProvider);
    if (!status.serviceEnabled) return 'Not turned on';
    final settings = ref.watch(limiterSettingsProvider);
    final today = status.day(DateTime.now());
    final total = settings.groups.fold<int>(
      0,
      (s, g) => s + (today[g.id] ?? 0),
    );
    return '${formatMinutes(total)} today';
  },
);
