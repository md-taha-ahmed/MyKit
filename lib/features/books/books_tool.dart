import 'package:flutter/material.dart';

import '../../core/tools/tool_definition.dart';
import 'books_routes.dart';

final booksTool = ToolDefinition(
  id: 'books',
  name: 'Books',
  description: 'PDF library with shelves, bookmarks and dark reading',
  icon: Icons.auto_stories,
  color: const Color(0xFFE0A33A),
  rootPath: BooksRoutes.home,
  routes: BooksRoutes.routes,
);
