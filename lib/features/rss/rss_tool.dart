import 'package:flutter/material.dart';

import '../../core/tools/tool_definition.dart';
import 'rss_routes.dart';

final rssTool = ToolDefinition(
  id: 'rss',
  name: 'RSS Feeds',
  description: 'Follow your favourite sites, sorted into categories',
  icon: Icons.rss_feed,
  color: const Color(0xFFFF8A3D),
  rootPath: RssRoutes.home,
  routes: RssRoutes.routes,
);
