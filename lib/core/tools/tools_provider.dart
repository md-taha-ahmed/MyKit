import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tool_definition.dart';

/// Tools shown on the dashboard.
///
/// Overridden in `main()` with `toolsRegistry` from `app/`, so features (like
/// the dashboard) can list tools without importing other features.
final toolsProvider = Provider<List<ToolDefinition>>(
  (ref) =>
      throw UnimplementedError('toolsProvider must be overridden in main()'),
);
