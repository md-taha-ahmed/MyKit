import 'package:flutter/material.dart';

import '../../core/tools/tool_definition.dart';
import 'music_routes.dart';
import 'presentation/providers/music_providers.dart';

final musicTool = ToolDefinition(
  id: 'music',
  name: 'Music',
  description: 'Play your songs folder by folder, even in the background',
  icon: Icons.library_music,
  color: const Color(0xFF1DB9A0),
  rootPath: MusicRoutes.home,
  routes: MusicRoutes.routes,
  status: (ref) {
    final playing = ref.watch(nowPlayingProvider).value;
    return playing == null ? null : '▶ ${playing.title}';
  },
);
