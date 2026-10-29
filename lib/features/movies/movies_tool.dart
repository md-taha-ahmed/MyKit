import 'package:flutter/material.dart';

import '../../core/tools/tool_definition.dart';
import 'movies_routes.dart';
import 'presentation/providers/movies_providers.dart';

final moviesTool = ToolDefinition(
  id: 'movies',
  name: 'Movies & Series (Beta)',
  description: 'Stremio add-ons: Torrentio streams, OpenSubtitles',
  icon: Icons.movie_filter,
  color: moviesAccent,
  rootPath: MoviesRoutes.home,
  routes: MoviesRoutes.routes,
  status: (ref) {
    final n = ref.watch(continueWatchingProvider).length;
    return n == 0 ? null : '$n in progress';
  },
);
