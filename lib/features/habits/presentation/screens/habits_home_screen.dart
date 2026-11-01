import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/i18n.dart';
import '../../domain/habit_analysis.dart';
import '../../domain/habit_models.dart';
import '../../habits_routes.dart';
import '../providers/habit_providers.dart';
import '../widgets/habit_widgets.dart';

/// The System: your level and stats, today's quests, hard days and the
/// weekly checks.
class HabitsHomeScreen extends ConsumerWidget {
  const HabitsHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(habitsProvider);
    final notifier = ref.read(habitsProvider.notifier);
    final now = DateTime.now();
    final today = habitDay(now);
    final yesterday = habitDay(now.subtract(const Duration(days: 1)));
    final hard = s.hardDay(today);
    final due = s.active.where((h) => h.dueOn(now)).toList();
    final notToday = s.active.where((h) => !h.dueOn(now)).toList();
    final unanswered = s.active
        .where(
          (h) =>
              h.dueOn(now.subtract(const Duration(days: 1))) &&
              !h.createdAt.isAfter(parseHabitDay(today)) &&
              s.checksOf(h.id)[yesterday] == null &&
              s.hardDay(yesterday) == null,
        )
        .toList();
    final weekly = s.active.where((h) => s.weeklyDue(h)).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('The System')),
        actions: [
          IconButton(
            tooltip: tr('What the System knows'),
            onPressed: () => context.push(HabitsRoutes.knows),
            icon: const Icon(Icons.psychology_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(HabitsRoutes.create),
        icon: const Icon(Icons.add),
        label: Text(tr('New quest')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        children: [
          const _StatusPanel(),
          _HardDayBar(day: today, hard: hard),
          if (notifier.lifeQuestionDue)
            SystemPanel(
              title: tr('[SYSTEM] WEEKLY CHECK-IN'),
              child: Row(
                children: [
                  Expanded(
                    child: Text(tr('Has anything changed in your life?')),
                  ),
                  TextButton(
                    onPressed: () => showLifeUpdate(context, ref),
                    child: Text(tr('Answer')),
                  ),
                ],
              ),
            ),
          if (s.active.isEmpty)
            SystemPanel(
              title: tr('[SYSTEM] NO QUESTS YET'),
              child: Text(
                tr(
                  'Create your first quest: one habit you want to build. Start small — the System will help you make it stick and learn what gets in your way.',
                ),
                style: const TextStyle(height: 1.5),
              ),
            ),
          if (unanswered.isNotEmpty) ...[
            _Header(tr('YESTERDAY — NOT ANSWERED')),
            for (final h in unanswered)
              QuestCard(habit: h, day: yesterday, hard: s.hardDay(yesterday)),
          ],
          if (due.isNotEmpty) ...[
            _Header(tr('DAILY QUESTS')),
            for (final h in due) QuestCard(habit: h, day: today, hard: hard),
          ],
          if (weekly.isNotEmpty) ...[
            _Header(tr('WEEKLY CHECK')),
            for (final h in weekly)
              SystemPanel(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr('How automatic is "{name}" now?', {'name': h.name}),
                      ),
                    ),
                    TextButton(
                      onPressed: () => showWeeklyCheck(context, ref, h),
                      child: Text(tr('Check')),
                    ),
                  ],
                ),
              ),
          ],
          if (notToday.isNotEmpty) ...[
            _Header(tr('NOT TODAY')),
            for (final h in notToday)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: RankBadge(
                  HabitAnalysis.rank(s.weeklyOf(h.id), h),
                  size: 30,
                ),
                title: Text(h.name),
                subtitle: Text(statLabel(h.stat)),
                onTap: () => context.push(HabitsRoutes.detail(h.id)),
              ),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
    child: Text(
      text,
      style: const TextStyle(
        color: habitsAccent,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        fontSize: 12.5,
      ),
    ),
  );
}

/// Level, XP and the four stats.
class _StatusPanel extends ConsumerWidget {
  const _StatusPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(habitPlayerProvider);
    final maxStat = p.stats.values.fold<int>(1, (a, b) => a > b ? a : b);
    return SystemPanel(
      title: tr('[SYSTEM] STATUS'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                tr('Level {level}', {'level': p.level.level}),
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              Text(
                '${p.level.into} / ${p.level.needed} XP',
                style: const TextStyle(color: Colors.white60),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: p.level.into / p.level.needed,
              minHeight: 6,
              color: habitsAccent,
            ),
          ),
          const SizedBox(height: 12),
          for (final stat in HabitStat.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 104,
                    child: Text(
                      statLabel(stat),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: p.stats[stat]! / maxStat,
                        minHeight: 5,
                        color: habitsAccent.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${p.stats[stat]}',
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// "Hard day" for everything: tiny versions only, misses excused.
class _HardDayBar extends ConsumerWidget {
  const _HardDayBar({required this.day, this.hard});

  final String day;
  final HardDay? hard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(habitsProvider.notifier);
    if (hard != null) {
      return SystemPanel(
        glow: Colors.orangeAccent,
        title: tr('[SYSTEM] HARD DAY MODE'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr(
                '{reason}. Only the tiny versions today, and misses are excused. Showing up at all counts.',
                {'reason': reasonLabel(hard!.reason)},
              ),
              style: const TextStyle(height: 1.45),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () => notifier.setHardDay(day, null),
                child: Text(tr('Turn off')),
              ),
            ),
          ],
        ),
      );
    }
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        onPressed: () async {
          final reason = await showModalBottomSheet<MissReason>(
            context: context,
            showDragHandle: true,
            builder: (sheet) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: Text(tr('Hard day today?')),
                    subtitle: Text(
                      tr(
                        'Only tiny versions are asked for and nothing counts as missed.',
                      ),
                    ),
                  ),
                  for (final r in [
                    MissReason.noPower,
                    MissReason.noInternet,
                    MissReason.security,
                    MissReason.moved,
                    MissReason.family,
                    MissReason.sick,
                    MissReason.tired,
                    MissReason.other,
                  ])
                    ListTile(
                      leading: const Icon(Icons.shield_outlined),
                      title: Text(reasonLabel(r)),
                      onTap: () => Navigator.pop(sheet, r),
                    ),
                ],
              ),
            ),
          );
          if (reason != null) await notifier.setHardDay(day, reason);
        },
        icon: const Icon(Icons.shield_outlined, size: 18),
        label: Text(tr('Hard day?')),
      ),
    );
  }
}
