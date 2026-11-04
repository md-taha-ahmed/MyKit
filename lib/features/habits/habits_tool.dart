import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import '../../core/tools/tool_definition.dart';
import 'domain/habit_models.dart';
import 'habits_routes.dart';
import 'presentation/providers/habit_providers.dart';

final habitsTool = ToolDefinition(
  id: 'habits',
  name: 'The System',
  description:
      'Build habits as daily quests, with a coach that learns why you get stuck',
  icon: Icons.bolt,
  color: habitsAccent,
  rootPath: HabitsRoutes.home,
  routes: HabitsRoutes.routes,
  onToggle: (ref, on) =>
      on ? ref.read(habitsProvider.notifier).resumeTool() : stopHabitsWork(ref),
  status: (ref) {
    final s = ref.watch(habitsProvider);
    final level = ref.watch(habitPlayerProvider).level.level;
    final now = DateTime.now();
    final due = s.active.where((h) => h.dueOn(now)).toList();
    if (due.isEmpty) {
      return s.active.isEmpty ? null : tr('Level {level}', {'level': level});
    }
    final today = habitDay(now);
    final done = due
        .where((h) => s.checksOf(h.id)[today]?.done ?? false)
        .length;
    return tr('{done}/{total} quests today · Lv {level}', {
      'done': done,
      'total': due.length,
      'level': level,
    });
  },
);
