import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n.dart';
import '../../domain/habit_models.dart';
import '../providers/habit_providers.dart';
import '../widgets/habit_widgets.dart';

/// Your aid kit: for each feeling, what helps — written by you. Use it when
/// the feeling hits, then say if it helped; the System learns which work.
class AidKitScreen extends ConsumerWidget {
  const AidKitScreen({super.key});

  static List<(String, String)> suggestions() => [
    ('😵', tr('Overstimulated')),
    ('😟', tr('Anxious')),
    ('😞', tr('Down / low')),
    ('😠', tr('Angry')),
    ('📱', tr('Urge to scroll')),
    ('🍔', tr('Craving food')),
    ('🌙', tr('Can\'t sleep')),
    ('😶', tr('Numb / empty')),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(habitsProvider);
    final notifier = ref.read(habitsProvider.notifier);
    final missing = suggestions()
        .where(
          (x) => !s.aidKit.any(
            (e) => e.feeling.toLowerCase() == x.$2.toLowerCase(),
          ),
        )
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text(tr('Aid kit'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newFeeling(context, ref),
        icon: const Icon(Icons.add),
        label: Text(tr('Feeling')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        children: [
          Text(
            tr(
              'Write what helps you for each feeling, in your own words. When it hits, open it here, do one, and say if it helped.',
            ),
            style: const TextStyle(color: Colors.white60, height: 1.5),
          ),
          const SizedBox(height: 12),
          if (missing.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (emoji, feeling) in missing)
                  ActionChip(
                    avatar: Text(emoji),
                    label: Text(feeling),
                    onPressed: () => notifier.addAidEntry(feeling, emoji),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          for (final e in s.aidKit) _EntryCard(entry: e),
        ],
      ),
    );
  }

  Future<void> _newFeeling(BuildContext context, WidgetRef ref) async {
    final feeling = TextEditingController();
    final emoji = TextEditingController(text: '🩹');
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('New feeling')),
        content: Row(
          children: [
            SizedBox(
              width: 56,
              child: TextField(
                controller: emoji,
                textAlign: TextAlign.center,
                decoration: InputDecoration(labelText: tr('Icon')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: feeling,
                autofocus: true,
                decoration: InputDecoration(labelText: tr('When I feel…')),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text(tr('Add')),
          ),
        ],
      ),
    );
    if (ok == true && feeling.text.trim().isNotEmpty) {
      await ref
          .read(habitsProvider.notifier)
          .addAidEntry(
            feeling.text,
            emoji.text.trim().isEmpty ? '🩹' : emoji.text.trim(),
          );
    }
  }
}

class _EntryCard extends ConsumerWidget {
  const _EntryCard({required this.entry});

  final AidEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(habitsProvider);
    final notifier = ref.read(habitsProvider.notifier);
    return SystemPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(entry.emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  entry.feeling,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'delete') await notifier.deleteAidEntry(entry.id);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'delete', child: Text(tr('Delete'))),
                ],
              ),
            ],
          ),
          if (entry.actions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                tr('What helps you when you feel this?'),
                style: const TextStyle(color: Colors.white54),
              ),
            ),
          for (final a in entry.actions)
            Builder(
              builder: (_) {
                final score = s.aidScore(a.id);
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.healing, color: habitsAccent),
                  title: Text(a.text),
                  subtitle: score.rated == 0
                      ? null
                      : Text(
                          tr('Helped {h} of {n} times', {
                            'h': score.helped,
                            'n': score.rated,
                          }),
                        ),
                  trailing: IconButton(
                    tooltip: tr('Remove'),
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => notifier.removeAidAction(entry.id, a.id),
                  ),
                );
              },
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () async {
                final c = TextEditingController();
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: Text(entry.feeling),
                    content: TextField(
                      controller: c,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: tr('What helps'),
                        hintText: tr('e.g. Do a chore, make wudu, go outside'),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(d, false),
                        child: Text(tr('Cancel')),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(d, true),
                        child: Text(tr('Add')),
                      ),
                    ],
                  ),
                );
                if (ok == true) await notifier.addAidAction(entry.id, c.text);
              },
              icon: const Icon(Icons.add, size: 18),
              label: Text(tr('Add what helps')),
            ),
          ),
        ],
      ),
    );
  }
}

/// "I feel…": pick the feeling, then one of your actions; later, say if it
/// helped.
Future<void> showFeelSheet(BuildContext context, WidgetRef ref) async {
  final s = ref.read(habitsProvider);
  if (s.aidKit.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(tr('Write your aid kit first.'))));
    return;
  }
  final entry = await showModalBottomSheet<AidEntry>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(title: Text(tr('[SYSTEM] What are you feeling?'))),
          for (final e in s.aidKit)
            ListTile(
              leading: Text(e.emoji, style: const TextStyle(fontSize: 22)),
              title: Text(e.feeling),
              subtitle: Text(
                tr('{n} things that help', {'n': e.actions.length}),
              ),
              onTap: () => Navigator.pop(sheet, e),
            ),
        ],
      ),
    ),
  );
  if (entry == null || !context.mounted) return;
  if (entry.actions.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr('Add what helps for this feeling first.'))),
    );
    return;
  }
  final action = await showModalBottomSheet<AidAction>(
    context: context,
    showDragHandle: true,
    builder: (sheet) {
      final st = ref.read(habitsProvider);
      // What has helped most comes first.
      final sorted = [...entry.actions]
        ..sort((a, b) {
          double rate(AidAction x) {
            final sc = st.aidScore(x.id);
            return sc.rated == 0 ? 0.5 : sc.helped / sc.rated;
          }

          return rate(b).compareTo(rate(a));
        });
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text('${entry.emoji} ${entry.feeling}'),
              subtitle: Text(tr('Pick one and do it now.')),
            ),
            for (final a in sorted)
              ListTile(
                leading: const Icon(Icons.healing, color: habitsAccent),
                title: Text(a.text),
                onTap: () => Navigator.pop(sheet, a),
              ),
          ],
        ),
      );
    },
  );
  if (action == null || !context.mounted) return;
  final notifier = ref.read(habitsProvider.notifier);
  await notifier.useAid(entry.id, action.id);
  if (!context.mounted) return;
  final helped = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(action.text),
      content: Text(tr('Go do it. When you\'re done, come back: did it help?')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Later'))),
        TextButton(
          onPressed: () => Navigator.pop(d, false),
          child: Text(tr('Not really')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(d, true),
          child: Text(tr('It helped')),
        ),
      ],
    ),
  );
  if (helped != null) await notifier.rateAid(action.id, helped);
}
