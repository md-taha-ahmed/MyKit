import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/tools/tool_definition.dart';

/// A plain dashboard tile: flat card, the tool's colour only on its icon,
/// and an optional live status line.
class ToolCard extends ConsumerWidget {
  const ToolCard({super.key, required this.tool, required this.onTap});

  final ToolDefinition tool;
  final VoidCallback onTap;

  static const _betaSuffix = ' (Beta)';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final beta = tool.name.endsWith(_betaSuffix);
    final name = beta
        ? tool.name.substring(0, tool.name.length - _betaSuffix.length)
        : tool.name;
    final status = tool.status?.call(ref);
    final onIcon =
        ThemeData.estimateBrightnessForColor(tool.color) == Brightness.light
        ? Colors.black
        : Colors.white;

    return Material(
      color: const Color(0xFF1C1E24),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: tool.color,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(tool.icon, color: onIcon, size: 24),
                  ),
                  const Spacer(),
                  if (beta)
                    const Text(
                      'Beta',
                      style: TextStyle(fontSize: 12, color: Colors.white38),
                    ),
                ],
              ),
              const Spacer(),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                status != null && status.isNotEmpty ? status : tool.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.3,
                  color: Colors.white60,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
