import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/tools/tool_definition.dart';
import '../../../../core/tools/tool_switch.dart';
import '../../../../core/tools/tools_provider.dart';

/// Turns whole sections of MyKit on or off: a turned-off section leaves the
/// dashboard and stops its notifications and background work. Its data stays.
class SectionsScreen extends ConsumerWidget {
  const SectionsScreen({super.key});

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    ToolDefinition tool,
    bool on,
  ) async {
    if (!on && tool.id == ToolIds.screenTime) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(tr('Turn off Screen time?')),
          content: Text(
            tr(
              'Your daily limits, focus hours and quest locks stop until you turn it back on.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: Text(tr('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: Text(tr('Turn off')),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await ref.read(disabledToolsProvider.notifier).setOn(tool, on);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final off = ref.watch(disabledToolsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr('App sections'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              tr(
                'A section you turn off leaves the home screen and stops its notifications and background work. Your data stays, and comes back when you turn it on.',
              ),
              style: const TextStyle(color: Colors.white70, height: 1.5),
            ),
          ),
          for (final tool in ref.watch(toolsProvider))
            SwitchListTile(
              secondary: Icon(tool.icon, color: tool.color),
              title: Text(tr(tool.name.replaceAll(' (Beta)', ''))),
              subtitle: Text(tr(tool.description)),
              value: !off.contains(tool.id),
              onChanged: (on) => _toggle(context, ref, tool, on),
            ),
        ],
      ),
    );
  }
}
