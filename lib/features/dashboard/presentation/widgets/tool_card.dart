import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/tools/tool_definition.dart';

/// A dashboard tile: tinted with the tool's colour, with a live status line.
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

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: tool.color.withValues(alpha: 0.18)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(
                tool.color.withValues(alpha: 0.20),
                const Color(0xFF1C1E24),
              ),
              const Color(0xFF181A1F),
            ],
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: tool.color.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: tool.color.withValues(alpha: 0.25),
                            blurRadius: 18,
                          ),
                        ],
                      ),
                      child: Icon(tool.icon, color: tool.color, size: 26),
                    ),
                    const Spacer(),
                    if (beta)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: tool.color.withValues(alpha: 0.6),
                          ),
                        ),
                        child: Text(
                          'BETA',
                          style: TextStyle(
                            fontSize: 9.5,
                            letterSpacing: 0.6,
                            fontWeight: FontWeight.w700,
                            color: tool.color,
                          ),
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  tool.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.3,
                    color: Colors.white54,
                  ),
                ),
                if (status != null && status.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: tool.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Color.lerp(tool.color, Colors.white, 0.35),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
