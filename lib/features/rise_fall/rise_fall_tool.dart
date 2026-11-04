import 'package:flutter/material.dart';

import '../../core/tools/tool_definition.dart';
import 'presentation/providers/rise_fall_providers.dart';
import 'rise_fall_routes.dart';

final riseFallTool = ToolDefinition(
  id: 'rise-fall',
  name: 'سقوط ونهوض',
  description: 'كيف سقطت الدول ثم نهضت: مشكلاتها الحقيقية وكيف حلّتها ببطء',
  icon: Icons.account_balance_outlined,
  color: riseFallAccent,
  rootPath: RiseFallRoutes.home,
  routes: RiseFallRoutes.routes,
  status: (ref) {
    final p = ref.watch(storyProgressProvider);
    final done = p.read.values.fold<int>(0, (s, parts) => s + parts.length);
    return done == 0 ? null : 'قرأت $done جزءاً';
  },
);
