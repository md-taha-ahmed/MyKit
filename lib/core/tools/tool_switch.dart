import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/shared_preferences_provider.dart';
import 'tool_definition.dart';
import 'tools_provider.dart';

/// Tool ids used outside their own feature.
abstract final class ToolIds {
  static const fitness = 'fitness';
  static const habits = 'habits';
  static const knowledge = 'knowledge';
  static const screenTime = 'screen-time';
}

/// Which tools are turned off in Settings. Saved as comma-separated ids, so
/// Android's side (`ToolSwitch.kt`) can read it too and background jobs can
/// check it without Riverpod. Turning a tool off never deletes its data.
abstract final class ToolSwitch {
  static const key = 'tools.disabled';

  static Set<String> disabled(SharedPreferences prefs) =>
      (prefs.getString(key) ?? '')
          .split(',')
          .where((s) => s.isNotEmpty)
          .toSet();

  static bool isOn(SharedPreferences prefs, String id) =>
      !disabled(prefs).contains(id);

  /// True when [path] belongs to a turned-off tool, so links from widgets
  /// and notifications can't open it.
  static bool blocks(
    String path,
    Iterable<ToolDefinition> tools,
    Set<String> off,
  ) => tools
      .where((t) => off.contains(t.id))
      .expand((t) => t.routes.whereType<GoRoute>())
      .any((r) => path == r.path || path.startsWith('${r.path}/'));
}

final disabledToolsProvider =
    NotifierProvider<DisabledToolsNotifier, Set<String>>(
      DisabledToolsNotifier.new,
    );

class DisabledToolsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() =>
      ToolSwitch.disabled(ref.read(sharedPreferencesProvider));

  Future<void> setOn(ToolDefinition tool, bool on) async {
    state = on ? ({...state}..remove(tool.id)) : {...state, tool.id};
    await ref
        .read(sharedPreferencesProvider)
        .setString(ToolSwitch.key, state.join(','));
    await tool.onToggle?.call(ref, on);
  }

  /// At startup: a restored backup may have turned tools off, or a job may
  /// have been left scheduled, so make sure the turned-off ones are quiet.
  Future<void> silenceDisabled() async {
    for (final tool in ref.read(toolsProvider)) {
      if (state.contains(tool.id)) await tool.onToggle?.call(ref, false);
    }
  }
}
