import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/widgets/dialogs.dart';
import '../../domain/habit_analysis.dart';
import '../../domain/habit_models.dart';
import '../../domain/patterns.dart';
import '../../habits_routes.dart';
import '../providers/habit_providers.dart';
import '../widgets/habit_widgets.dart';

/// One quest: rank and stage, the last five weeks, patterns, what got in
/// the way, what the System understands and what it changed.
class HabitDetailScreen extends ConsumerWidget {
  const HabitDetailScreen({super.key, required this.habitId});

  final String habitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(habitsProvider);
    final habit = s.habit(habitId);
    if (habit == null) {
      return Scaffold(appBar: AppBar(), body: const SizedBox.shrink());
    }
    final notifier = ref.read(habitsProvider.notifier);
    final checks = s.checksOf(habitId);
    final weekly = s.weeklyOf(habitId);
    final rank = HabitAnalysis.rank(weekly, habit);
    final streak = HabitAnalysis.streak(habit, checks, s.hardDayKeys);
    final rate = HabitAnalysis.rate(checks.values);
    final reasons = HabitAnalysis.reasons(checks.values);
    final byWeekday = HabitAnalysis.byWeekday(checks.values);
    final understanding = s.understanding[habitId];
    final notes = s.notesOf(habitId);
    final days = (DateTime.now().difference(habit.createdAt).inDays + 1);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(habit.name),
        actions: [
          IconButton(
            tooltip: tr('Edit'),
            onPressed: () => context.push(HabitsRoutes.edit(habitId)),
            icon: const Icon(Icons.edit_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'archive') {
                await notifier.archive(habitId, archived: !habit.archived);
              } else if (v == 'delete') {
                final ok = await showConfirmDialog(
                  context,
                  title: tr('Delete "{name}"?', {'name': habit.name}),
                  message: tr(
                    'Its history and what the System learned about it are deleted too.',
                  ),
                );
                if (ok) {
                  await notifier.delete(habitId);
                  if (context.mounted) context.pop();
                }
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'archive',
                child: Text(habit.archived ? tr('Restore') : tr('Pause quest')),
              ),
              PopupMenuItem(value: 'delete', child: Text(tr('Delete'))),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(HabitsRoutes.talk(habitId)),
        icon: const Icon(Icons.forum_outlined),
        label: Text(tr('Talk to the System')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        children: [
          SystemPanel(
            child: Row(
              children: [
                RankBadge(rank, size: 56),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('Rank {rank} · {stage}', {
                          'rank': rank.letter,
                          'stage': rankStage(rank),
                        }),
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        weekly.isEmpty
                            ? tr('Rank comes from the weekly check.')
                            : tr('Automaticity {n} / 7', {
                                'n': weekly.last.average.toStringAsFixed(1),
                              }),
                        style: const TextStyle(color: Colors.white60),
                      ),
                      Text(
                        tr(
                          'Day {days} · most habits take about 2 months, some much longer — your own pace is fine.',
                          {'days': days},
                        ),
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (DayPatterns.typicalTime(checks.values) case final typical?
              when habit.reminderMinutes != null &&
                  (typical - habit.reminderMinutes!).abs() >= 60)
            SystemPanel(
              title: tr('[SYSTEM] BETTER REMINDER TIME'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    tr(
                      'You usually do it around {typical}, but the reminder is at {reminder}. Reminders work best right before you actually do it.',
                      {
                        'typical': _hhmm(typical),
                        'reminder': _hhmm(habit.reminderMinutes!),
                      },
                    ),
                    style: const TextStyle(height: 1.45),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton(
                      onPressed: () => notifier.moveReminder(
                        habitId,
                        // A little before you usually do it.
                        (typical - 15).clamp(0, 1439),
                      ),
                      child: Text(
                        tr('Move to {time}', {
                          'time': _hhmm((typical - 15).clamp(0, 1439)),
                        }),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              _Number(tr('Streak'), '$streak'),
              _Number(
                tr('Done (30 days)'),
                rate == null ? '—' : '${(rate * 100).round()}%',
              ),
              _Number(tr('Weekly checks'), '${weekly.length}'),
            ],
          ),
          const SizedBox(height: 12),
          SystemPanel(
            title: tr('LAST 5 WEEKS'),
            child: _Grid(habit: habit, checks: checks, s: s),
          ),
          if (weekly.length >= 2)
            SystemPanel(
              title: tr('HOW AUTOMATIC IT FEELS'),
              child: SizedBox(
                height: 60,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final w in weekly.reversed.take(12).toList().reversed)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: FractionallySizedBox(
                            heightFactor: w.average / 7,
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              decoration: BoxDecoration(
                                color: habitsAccent.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (reasons.isNotEmpty)
            SystemPanel(
              title: tr('WHAT GOT IN THE WAY'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (r, n) in reasons.take(5))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(child: Text(reasonLabel(r))),
                          Text('×$n'),
                        ],
                      ),
                    ),
                  if (HabitAnalysis.adviceFor(reasons.first.$1)
                      case final advice?)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        tr(advice),
                        style: const TextStyle(
                          color: habitsAccent,
                          height: 1.45,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (byWeekday.length >= 3)
            SystemPanel(
              title: tr('BY DAY OF THE WEEK'),
              child: Row(
                children: [
                  for (final d in [6, 7, 1, 2, 3, 4, 5])
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            byWeekday[d] == null
                                ? '—'
                                : '${(byWeekday[d]! * 100).round()}%',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            tr(
                              const {
                                6: 'Sat',
                                7: 'Sun',
                                1: 'Mon',
                                2: 'Tue',
                                3: 'Wed',
                                4: 'Thu',
                                5: 'Fri',
                              }[d]!,
                            ),
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          SystemPanel(
            title: tr('WHAT THE SYSTEM UNDERSTANDS'),
            child: understanding == null || understanding.isEmpty
                ? Text(
                    tr(
                      'Nothing yet. After a talk, the System writes down why you get stuck and what helps — and sharpens it every time.',
                    ),
                    style: const TextStyle(color: Colors.white60),
                  )
                : UnderstandingView(habitId: habitId, u: understanding),
          ),
          SystemPanel(
            title: tr('THE PLAN'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (habit.identity.isNotEmpty)
                  Text(
                    tr('I\'m someone who {identity}', {
                      'identity': habit.identity,
                    }),
                  ),
                Text(tr('After {anchor}', {'anchor': habit.anchor})),
                Text(tr('Full: {full}', {'full': habit.full})),
                Text(tr('Tiny: {tiny}', {'tiny': habit.tiny})),
                for (final o in habit.obstacles)
                  Text(
                    tr('If {when}, then {then}', {
                      'when': o.when,
                      'then': o.then,
                    }),
                    style: const TextStyle(color: Colors.white70),
                  ),
              ],
            ),
          ),
          if (notes.isNotEmpty)
            SystemPanel(
              title: tr('PAST TALKS'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final n in notes.take(8))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            habitDay(n.date),
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                          Text(n.insight, style: const TextStyle(height: 1.4)),
                          for (final c in n.changes)
                            Text(
                              '↳ $c',
                              style: const TextStyle(
                                color: habitsAccent,
                                fontSize: 12.5,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          OutlinedButton.icon(
            onPressed: () => showWeeklyCheck(context, ref, habit),
            icon: const Icon(Icons.speed),
            label: Text(tr('Weekly check now')),
          ),
        ],
      ),
    );
  }
}

String _hhmm(int m) =>
    '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

class _Number extends StatelessWidget {
  const _Number(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    ),
  );
}

/// 5 weeks of days: done, tiny, missed, excused, not due.
class _Grid extends StatelessWidget {
  const _Grid({required this.habit, required this.checks, required this.s});

  final Habit habit;
  final Map<String, CheckIn> checks;
  final HabitsState s;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final days = [
      for (var i = 34; i >= 0; i--) today.subtract(Duration(days: i)),
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final d in days)
          Builder(
            builder: (_) {
              final key = habitDay(d);
              final c = checks[key];
              final due = habit.weekdays.contains(d.weekday);
              final color = switch (c?.status) {
                CheckStatus.full => Colors.greenAccent,
                CheckStatus.tiny => Colors.green.shade700,
                CheckStatus.missed => Colors.redAccent,
                CheckStatus.excused => Colors.orangeAccent,
                null =>
                  s.hardDayKeys.contains(key)
                      ? Colors.orange.shade900
                      : due
                      ? Colors.white12
                      : Colors.transparent,
              };
              return Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(6),
                  border: key == habitDay(today)
                      ? Border.all(color: habitsAccent)
                      : null,
                ),
                child: Text('${d.day}', style: const TextStyle(fontSize: 11)),
              );
            },
          ),
      ],
    );
  }
}

/// What the System understands about a habit — readable and correctable.
class UnderstandingView extends ConsumerWidget {
  const UnderstandingView({super.key, required this.habitId, required this.u});

  final String habitId;
  final HabitUnderstanding u;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget part(String label, String text) => text.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: habitsAccent, fontSize: 12.5),
                ),
                Text(text, style: const TextStyle(height: 1.45)),
              ],
            ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        part(tr('Root cause'), u.rootCause),
        part(tr('Evidence'), u.evidence),
        part(tr('What helps'), u.helps),
        part(tr('What doesn\'t'), u.fails),
        Row(
          children: [
            Text(
              tr('Confidence {n}%', {'n': u.confidence}),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => _correct(context, ref),
              child: Text(tr('Correct it')),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _correct(BuildContext context, WidgetRef ref) async {
    final root = TextEditingController(text: u.rootCause);
    final helps = TextEditingController(text: u.helps);
    final fails = TextEditingController(text: u.fails);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('Correct the System')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: root,
                maxLines: 3,
                decoration: InputDecoration(labelText: tr('Root cause')),
              ),
              TextField(
                controller: helps,
                maxLines: 3,
                decoration: InputDecoration(labelText: tr('What helps')),
              ),
              TextField(
                controller: fails,
                maxLines: 3,
                decoration: InputDecoration(labelText: tr('What doesn\'t')),
              ),
            ],
          ),
        ),
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
    if (ok != true) return;
    await ref
        .read(habitsProvider.notifier)
        .editUnderstanding(
          habitId,
          HabitUnderstanding(
            rootCause: root.text.trim(),
            evidence: u.evidence,
            helps: helps.text.trim(),
            fails: fails.text.trim(),
            // Your own correction: the System builds on it.
            confidence: 90,
            updatedAt: DateTime.now(),
          ),
        );
  }
}
