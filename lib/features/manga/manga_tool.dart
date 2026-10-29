import 'package:flutter/material.dart';

import '../../core/tools/tool_definition.dart';
import 'manga_routes.dart';

final mangaTool = ToolDefinition(
  id: 'manga',
  name: 'Anime & Manga (Beta)',
  description: 'Mihon & Aniyomi extensions: read manga, watch anime',
  icon: Icons.menu_book,
  color: const Color(0xFFE5484D),
  rootPath: MangaRoutes.home,
  routes: MangaRoutes.routes,
);
