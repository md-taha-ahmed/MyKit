import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n.dart';
import '../providers/habit_providers.dart';
import '../widgets/habit_widgets.dart';
import 'habit_detail_screen.dart';

/// Everything the System knows about you: your life context and its
/// understanding of each quest. You can read and correct all of it. It
/// stays on this phone (and your Drive backup); a short summary is sent to
/// Gemini only when you talk to the System.
class SystemKnowsScreen extends ConsumerWidget {
  const SystemKnowsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(habitsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr('What the System knows'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Text(
            tr(
              'Kept on this phone and in your Drive backup. When you talk to the System, a short summary of this and your recent days is sent to Gemini.',
            ),
            style: const TextStyle(color: Colors.white60, height: 1.45),
          ),
          const SizedBox(height: 12),
          SystemPanel(
            title: tr('YOUR LIFE'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  s.life.summary.isEmpty
                      ? tr(
                          'Not told yet. Tell the System about your situation — it uses it to understand your days.',
                        )
                      : s.life.summary,
                  style: TextStyle(
                    height: 1.5,
                    color: s.life.summary.isEmpty ? Colors.white60 : null,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => showLifeUpdate(context, ref),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(tr('Tell it something new')),
                    ),
                    const Spacer(),
                    if (s.life.summary.isNotEmpty)
                      TextButton(
                        onPressed: () => _edit(context, ref, s.life.summary),
                        child: Text(tr('Correct it')),
                      ),
                  ],
                ),
              ],
            ),
          ),
          for (final h in s.habits)
            if (s.understanding[h.id] case final u? when !u.isEmpty)
              SystemPanel(
                title: h.name.toUpperCase(),
                child: UnderstandingView(habitId: h.id, u: u),
              ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, String text) async {
    final c = TextEditingController(text: text);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('Your life')),
        content: TextField(controller: c, minLines: 4, maxLines: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text(tr('Save')),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(habitsProvider.notifier).editLife(c.text);
  }
}
