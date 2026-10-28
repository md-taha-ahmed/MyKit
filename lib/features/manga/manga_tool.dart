import 'package:flutter/material.dart';

import '../../core/tools/tool_definition.dart';
import 'manga_routes.dart';

final mangaTool = ToolDefinition(
  id: 'manga',
  name: 'Manga (Beta)',
  description: 'Mihon-compatible extensions, browser and reader',
  icon: Icons.menu_book,
  color: const Color(0xFFE5484D),
  rootPath: MangaRoutes.home,
  routes: MangaRoutes.routes,
);
