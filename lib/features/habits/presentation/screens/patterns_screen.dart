import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n.dart';
import '../../domain/patterns.dart';
import '../providers/habit_providers.dart';
import '../widgets/habit_widgets.dart';

/// Patterns across your days: what's different on heavy-scrolling days
/// (your "down" signal) — from your own data, with how many days it's
/// based on.
class PatternsScreen extends ConsumerWidget {
  const PatternsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(habitsProvider);
    final usual = DayPatterns.usualSocial(s.days);
    final patterns = s.patterns;
    final day = s.understanding[dayTalkId];

    return Scaffold(
      appBar: AppBar(title: Text(tr('Patterns'))),
      body: RefreshIndicator(
        onRefresh: ref.read(habitsProvider.notifier).recordDays,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Text(
              usual == null
                  ? tr(
                      'Patterns appear after about a week of days with Screen time on. Keep using MyKit as usual.',
                    )
                  : tr(
                      'Your usual social media: ~{n} min a day. A "heavy" day is 1.5× that or more — often a sign of a low day.',
                      {'n': usual},
                    ),
              style: const TextStyle(color: Colors.white70, height: 1.5),
            ),
            const SizedBox(height: 12),
            if (day != null && !day.isEmpty)
              SystemPanel(
                title: tr('YOUR DOWN-DAY PATTERN'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(day.rootCause, style: const TextStyle(height: 1.5)),
                    if (day.helps.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        tr('What helps: {helps}', {'helps': day.helps}),
                        style: const TextStyle(color: habitsAccent),
                      ),
                    ],
                  ],
                ),
              ),
            for (final p in patterns)
              SystemPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      tr(p.text),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    _Bar(
                      label: tr('Heavy-scrolling days'),
                      value: p.onHeavy,
                      color: Colors.orangeAccent,
                    ),
                    _Bar(
                      label: tr('Other days'),
                      value: p.onNormal,
                      color: habitsAccent,
                    ),
                    Text(
                      tr('Based on {h} heavy and {n} other days.', {
                        'h': p.heavyDays,
                        'n': p.normalDays,
                      }),
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            if (usual != null && patterns.isEmpty)
              Text(
                tr('No clear differences yet. That can be good news.'),
                style: const TextStyle(color: Colors.white60),
              ),
            const SizedBox(height: 8),
            Text(
              tr(
                'These are links in your data, not proof of cause. Talk to the System about a day to find what\'s really behind it.',
              ),
              style: const TextStyle(color: Colors.white38, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.label, required this.value, required this.color});

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        SizedBox(
          width: 130,
          child: Text(label, style: const TextStyle(fontSize: 12.5)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 8,
              color: color,
            ),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            '${(value * 100).round()}%',
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 12.5),
          ),
        ),
      ],
    ),
  );
}
