import 'package:flutter/material.dart';

import '../../core/tools/tool_definition.dart';
import 'rss_routes.dart';
import 'presentation/providers/rss_providers.dart';

final rssTool = ToolDefinition(
  id: 'rss',
  name: 'RSS Feeds',
  description: 'Follow your favourite sites, sorted into categories',
  icon: Icons.rss_feed,
  color: const Color(0xFFFF8A3D),
  rootPath: RssRoutes.home,
  routes: RssRoutes.routes,
  status: (ref) {
    if (ref.watch(rssLibraryProvider).feeds.isEmpty) return null;
    final unread = ref.watch(unreadCountProvider(allArticles));
    return unread == 0 ? 'All caught up' : '$unread unread';
  },
);
