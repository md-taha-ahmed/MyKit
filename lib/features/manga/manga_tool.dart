import 'package:flutter/material.dart';

import '../../core/tools/tool_definition.dart';
import 'manga_routes.dart';
import 'presentation/providers/anime_providers.dart';
import 'presentation/providers/manga_providers.dart';

final mangaTool = ToolDefinition(
  id: 'manga',
  name: 'Anime & Manga (Beta)',
  description: 'Mihon & Aniyomi extensions: read manga, watch anime',
  icon: Icons.menu_book,
  color: const Color(0xFFE5484D),
  rootPath: MangaRoutes.home,
  routes: MangaRoutes.routes,
  status: (ref) {
    final manga = ref.watch(mangaLibraryProvider).length;
    final anime = ref.watch(animeLibraryProvider).length;
    final parts = [
      if (manga > 0) '$manga manga',
      if (anime > 0) '$anime anime',
    ];
    return parts.isEmpty ? null : '${parts.join(' · ')} in library';
  },
);
