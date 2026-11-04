import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import '../../core/tools/tool_definition.dart';
import 'books_routes.dart';
import 'presentation/providers/books_providers.dart';

final booksTool = ToolDefinition(
  id: 'books',
  name: 'Books',
  description: 'PDF library with shelves, bookmarks and dark reading',
  icon: Icons.auto_stories,
  color: const Color(0xFFE0A33A),
  rootPath: BooksRoutes.home,
  routes: BooksRoutes.routes,
  status: (ref) {
    final reading = ref.watch(continueReadingProvider).firstOrNull;
    if (reading != null) {
      return tr('Reading: {title}', {'title': reading.title});
    }
    final n = ref.watch(booksLibraryProvider).books.length;
    return n == 0
        ? null
        : n == 1
        ? tr('1 book')
        : tr('{n} books', {'n': n});
  },
);
