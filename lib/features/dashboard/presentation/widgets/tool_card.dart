import 'package:flutter/material.dart';

import '../../../../core/tools/tool_definition.dart';

class ToolCard extends StatelessWidget {
  const ToolCard({super.key, required this.tool, required this.onTap});

  final ToolDefinition tool;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: tool.color.withValues(alpha: .2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(tool.icon, color: tool.color, size: 28),
              ),
              const Spacer(),
              Text(tool.name, style: text.titleMedium),
              const SizedBox(height: 4),
              Text(
                tool.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(color: Colors.white60),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Placeholder tile hinting that more tools are on the way.
class ComingSoonCard extends StatelessWidget {
  const ComingSoonCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12, width: 1.5),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_circle_outline, color: Colors.white30, size: 32),
          SizedBox(height: 8),
          Text('More tools soon', style: TextStyle(color: Colors.white38)),
        ],
      ),
    );
  }
}
