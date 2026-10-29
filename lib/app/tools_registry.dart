import '../core/tools/tool_definition.dart';
import '../features/books/books_tool.dart';
import '../features/countdown/countdown_tool.dart';
import '../features/fitness/fitness_tool.dart';
import '../features/manga/manga_tool.dart';
import '../features/movies/movies_tool.dart';
import '../features/music/music_tool.dart';
import '../features/rss/rss_tool.dart';

/// All tools available in the app, in dashboard order.
///
/// Lives in `app/` (not `core/`) because it composes features; `core/` must
/// never import from `features/`.
///
/// To add a new tool: create `lib/features/<tool>/` with its own
/// domain/data/presentation layers, expose a `ToolDefinition`, and add it here.
final List<ToolDefinition> toolsRegistry = [
  countdownTool,
  rssTool,
  musicTool,
  booksTool,
  mangaTool,
  moviesTool,
  fitnessTool,
];
