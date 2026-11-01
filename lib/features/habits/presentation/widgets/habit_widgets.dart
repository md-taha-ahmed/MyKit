import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/i18n.dart';
import '../../domain/habit_analysis.dart';
import '../../domain/habit_models.dart';
import '../../habits_routes.dart';
import '../providers/habit_providers.dart';

/// A "System window": dark panel with a glowing blue edge.
class SystemPanel extends StatelessWidget {
  const SystemPanel({
    super.key,
    required this.child,
    this.title,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 16),
    this.glow = habitsAccent,
  });

  final Widget child;
  final String? title;
  final EdgeInsets padding;
  final Color glow;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      color: const Color(0xFF0D1626),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: glow.withValues(alpha: 0.55)),
      boxShadow: [
        BoxShadow(color: glow.withValues(alpha: 0.18), blurRadius: 14),
      ],
    ),
    padding: padding,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          Text(
            title!,
            style: TextStyle(
              color: glow,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
        ],
        child,
      ],
    ),
  );
}

/// Rank badge (E … S), coloured like a hunter rank.
class RankBadge extends StatelessWidget {
  const RankBadge(this.rank, {super.key, this.size = 34});

  final HabitRank rank;
  final double size;

  static const colors = {
    HabitRank.e: Color(0xFF9E9E9E),
    HabitRank.d: Color(0xFF81C784),
    HabitRank.c: Color(0xFF4FC3F7),
    HabitRank.b: Color(0xFF9575CD),
    HabitRank.a: Color(0xFFFFB74D),
    HabitRank.s: Color(0xFFFF5252),
  };

  @override
  Widget build(BuildContext context) {
    final c = colors[rank]!;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: c, width: 2),
        color: c.withValues(alpha: 0.12),
      ),
      child: Text(
        rank.letter,
        style: TextStyle(
          color: c,
          fontWeight: FontWeight.w900,
          fontSize: size * 0.45,
        ),
      ),
    );
  }
}

String rankStage(HabitRank r) => switch (r) {
  HabitRank.e => tr('Awakening'),
  HabitRank.d => tr('Starting'),
  HabitRank.c => tr('Building'),
  HabitRank.b => tr('Getting stronger'),
  HabitRank.a => tr('Almost automatic'),
  HabitRank.s => tr('Automatic'),
};

String statLabel(HabitStat s) => tr(s.label);

String reasonLabel(MissReason r) => tr(r.label);

/// One of today's quests: its versions, anchor, and the three answers.
class QuestCard extends ConsumerWidget {
  const QuestCard({
    super.key,
    required this.habit,
    required this.day,
    this.hard,
  });

  final Habit habit;
  final String day;

  /// Today is a hard day: only the tiny version is asked for.
  final HardDay? hard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(habitsProvider);
    final checks = s.checksOf(habit.id);
    final check = checks[day];
    final rank = HabitAnalysis.rank(s.weeklyOf(habit.id), habit);
    final streak = HabitAnalysis.streak(habit, checks, s.hardDayKeys);
    final today = day == habitDay(DateTime.now());
    final recovery = today && HabitAnalysis.recoveryToday(habit, checks);
    final notifier = ref.read(habitsProvider.notifier);
    final theme = Theme.of(context);

    return SystemPanel(
      glow: check?.done ?? false
          ? Colors.greenAccent
          : recovery
          ? Colors.orangeAccent
          : habitsAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => context.push(HabitsRoutes.detail(habit.id)),
            child: Row(
              children: [
                RankBadge(rank),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        habit.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        [
                          statLabel(habit.stat),
                          if (streak > 0) '🔥 $streak',
                          if (recovery) tr('Recovery quest'),
                        ].join(' · '),
                        style: TextStyle(
                          color: recovery
                              ? Colors.orangeAccent
                              : Colors.white60,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white38),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (habit.anchor.isNotEmpty)
            Text(
              tr('After {anchor}', {'anchor': habit.anchor}),
              style: const TextStyle(color: habitsAccent, fontSize: 13),
            ),
          const SizedBox(height: 4),
          if (habit.breaking)
            Text('▸ ${habit.full}', style: const TextStyle(height: 1.4))
          else ...[
            if (hard == null && !recovery)
              Text('▸ ${habit.full}', style: const TextStyle(height: 1.4)),
            Text(
              tr('▸ Tiny: {tiny}', {'tiny': habit.tiny}),
              style: TextStyle(
                height: 1.4,
                color: hard != null || recovery ? null : Colors.white60,
                fontWeight: hard != null || recovery ? FontWeight.w600 : null,
              ),
            ),
          ],
          if (recovery && hard == null && !habit.breaking)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                tr('Never miss twice: the tiny version is enough today.'),
                style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 12.5,
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (check != null)
            Row(
              children: [
                Icon(switch (check.status) {
                  CheckStatus.full => Icons.check_circle,
                  CheckStatus.tiny => Icons.check_circle_outline,
                  CheckStatus.missed => Icons.cancel_outlined,
                  CheckStatus.excused => Icons.shield_outlined,
                }, color: check.done ? Colors.greenAccent : Colors.white54),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(switch (check.status) {
                    CheckStatus.full =>
                      check.auto
                          ? tr('Done (from your workout) +{xp} XP', {
                              'xp': HabitAnalysis.fullXp,
                            })
                          : tr('Quest complete +{xp} XP', {
                              'xp': HabitAnalysis.fullXp,
                            }),
                    CheckStatus.tiny => tr('Tiny version done +{xp} XP', {
                      'xp': HabitAnalysis.tinyXp,
                    }),
                    CheckStatus.missed => tr('Missed: {reason}', {
                      'reason': check.reason == null
                          ? '—'
                          : reasonLabel(check.reason!),
                    }),
                    CheckStatus.excused => tr('Excused: {reason}', {
                      'reason': check.reason == null
                          ? '—'
                          : reasonLabel(check.reason!),
                    }),
                  }),
                ),
                if (check.status == CheckStatus.missed)
                  TextButton(
                    onPressed: () => context.push(HabitsRoutes.talk(habit.id)),
                    child: Text(tr('Talk')),
                  ),
                IconButton(
                  tooltip: tr('Undo'),
                  onPressed: () => notifier.clearCheck(habit.id, day),
                  icon: const Icon(Icons.undo, size: 20),
                ),
              ],
            )
          else if (habit.breaking)
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () =>
                        notifier.checkIn(habit.id, day, CheckStatus.full),
                    child: Text(tr('Stayed clean')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => showMissSheet(context, ref, habit, day),
                    child: Text(tr('Slipped')),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                if (hard == null) ...[
                  Expanded(
                    child: FilledButton(
                      onPressed: () =>
                          notifier.checkIn(habit.id, day, CheckStatus.full),
                      child: Text(tr('Done')),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: () =>
                        notifier.checkIn(habit.id, day, CheckStatus.tiny),
                    child: Text(tr('Tiny')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => showMissSheet(context, ref, habit, day),
                    child: Text(tr('Missed')),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// "What got in the way?": a reason, a note and your mood. Outside reasons
/// excuse the day; then the System offers to talk.
Future<void> showMissSheet(
  BuildContext context,
  WidgetRef ref,
  Habit habit,
  String day,
) async {
  MissReason? reason;
  var mood = 3;
  final note = TextEditingController();
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, set) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(sheet).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr('[SYSTEM] What got in the way?'),
                style: const TextStyle(
                  color: habitsAccent,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                tr(
                  'No judgement. Knowing the real reason is how the quest gets easier.',
                ),
                style: const TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final r in MissReason.values)
                    ChoiceChip(
                      label: Text(reasonLabel(r)),
                      selected: reason == r,
                      onSelected: (_) => set(() => reason = r),
                    ),
                ],
              ),
              if (reason?.external ?? false)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    tr(
                      'That\'s outside your control: the day is excused, not a failure.',
                    ),
                    style: const TextStyle(color: Colors.greenAccent),
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: tr('What happened? (optional)'),
                ),
              ),
              const SizedBox(height: 12),
              Text(tr('How do you feel today?')),
              Slider(
                value: mood.toDouble(),
                min: 1,
                max: 5,
                divisions: 4,
                label: const ['😞', '😕', '😐', '🙂', '😄'][mood - 1],
                onChanged: (v) => set(() => mood = v.round()),
              ),
              FilledButton(
                onPressed: reason == null
                    ? null
                    : () => Navigator.pop(sheet, true),
                child: Text(tr('Save')),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (result != true || reason == null) return;
  final r = reason!;
  await ref
      .read(habitsProvider.notifier)
      .checkIn(
        habit.id,
        day,
        r.external ? CheckStatus.excused : CheckStatus.missed,
        reason: r,
        note: note.text.trim(),
        mood: mood,
      );
  if (!context.mounted || r.external) return;
  final talk = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(tr('Talk to the System?')),
      content: Text(
        tr(
          'It will ask a couple of questions, look at your history and suggest how to make this quest doable.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(d, false),
          child: Text(tr('Not now')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(d, true),
          child: Text(tr('Talk')),
        ),
      ],
    ),
  );
  if (talk == true && context.mounted) {
    await context.push(HabitsRoutes.talk(habit.id));
  }
}

/// The weekly "how automatic is it?" check (SRBAI, 1–7 each).
Future<void> showWeeklyCheck(
  BuildContext context,
  WidgetRef ref,
  Habit habit,
) async {
  final items = [
    tr('I do it automatically.'),
    tr('I do it without having to consciously remember.'),
    tr('I do it without thinking.'),
    tr('I start doing it before I realise I\'m doing it.'),
  ];
  final scores = [4, 4, 4, 4];
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, set) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr('[SYSTEM] Weekly check: {name}', {'name': habit.name}),
                style: const TextStyle(
                  color: habitsAccent,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                tr(
                  'How true is each one this week? 1 = not at all, 7 = completely. This is how your rank is measured.',
                ),
                style: const TextStyle(color: Colors.white60),
              ),
              for (final (i, item) in items.indexed) ...[
                const SizedBox(height: 12),
                Text(item),
                Slider(
                  value: scores[i].toDouble(),
                  min: 1,
                  max: 7,
                  divisions: 6,
                  label: '${scores[i]}',
                  onChanged: (v) => set(() => scores[i] = v.round()),
                ),
              ],
              FilledButton(
                onPressed: () => Navigator.pop(sheet, true),
                child: Text(
                  tr('Save +{xp} XP', {'xp': HabitAnalysis.weeklyCheckXp}),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (ok == true) {
    await ref.read(habitsProvider.notifier).addWeekly(habit.id, scores);
  }
}

/// "Has anything changed in your life?" — folded into what the System
/// knows about you.
Future<void> showLifeUpdate(BuildContext context, WidgetRef ref) async {
  final text = TextEditingController();
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(sheet).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr('[SYSTEM] Has anything changed in your life?'),
            style: const TextStyle(
              color: habitsAccent,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tr(
              'Where you are, your routine, power or internet, work, family, how you feel… The System uses it to understand your days.',
            ),
            style: const TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: text,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(hintText: tr('Nothing new, or…')),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => Navigator.pop(sheet, true),
            child: Text(tr('Save')),
          ),
        ],
      ),
    ),
  );
  if (ok == true) await ref.read(habitsProvider.notifier).tellLife(text.text);
}
