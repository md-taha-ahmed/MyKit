import 'package:flutter/material.dart';

import '../../domain/services/reading_time.dart';

/// "3 min" pill, green / amber / red for short / medium / long reads; grey
/// "Preview" when the feed only gives a teaser.
class ReadingTimeBadge extends StatelessWidget {
  const ReadingTimeBadge(this.time, {super.key});

  final ReadingTime time;

  static const _colors = {
    ReadingLength.preview: Color(0xFF8A8D96),
    ReadingLength.short: Color(0xFF4CC38A),
    ReadingLength.medium: Color(0xFFE5A93A),
    ReadingLength.long: Color(0xFFE5675C),
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[time.length]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            time.length == ReadingLength.preview
                ? Icons.short_text
                : Icons.schedule,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 3),
          Text(
            time.label,
            // Always "3 min", even inside an Arabic (RTL) card.
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
