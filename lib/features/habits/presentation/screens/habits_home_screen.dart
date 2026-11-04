import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/i18n.dart';
import '../../domain/habit_analysis.dart';
import '../../domain/habit_models.dart';
import '../../habits_routes.dart';
import '../providers/habit_providers.dart';
import '../widgets/habit_widgets.dart';
import '../../../../core/ai/gemini_client.dart';
import '../../../../core/ai/gemini_key_screen.dart';
import '../../../../core/storage/shared_preferences_provider.dart';
import '../../../../core/widgets/simple_markdown.dart';
import '../../data/app_signals.dart';
import '../../data/nudges.dart';
import '../../domain/patterns.dart';
import 'aid_kit_screen.dart';
import 'tasks_screen.dart';

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
            tooltip: tr('To-do'),
            onPressed: () => context.push(HabitsRoutes.tasks),
            icon: const Icon(Icons.checklist),
          ),
          IconButton(
            tooltip: tr('Aid kit'),
            onPressed: () => context.push(HabitsRoutes.aidKit),
            icon: const Icon(Icons.medical_services_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'knows':
                  context.push(HabitsRoutes.knows);
                case 'patterns':
                  context.push(HabitsRoutes.patterns);
                case 'nudges':
                  final prefs = ref.read(sharedPreferencesProvider);
                  final on = !Nudges.enabled(prefs);
                  await prefs.setBool(Nudges.enabledKey, on);
                  await Nudges.sync(enabled: on);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          on
                              ? tr('Reminders for unfinished things are on.')
                              : tr('Reminders for unfinished things are off.'),
                        ),
                      ),
                    );
                  }
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'knows',
                child: Text(tr('What the System knows')),
              ),
              PopupMenuItem(value: 'patterns', child: Text(tr('Patterns'))),
              PopupMenuItem(
                value: 'nudges',
                child: Text(
                  Nudges.enabled(ref.read(sharedPreferencesProvider))
                      ? tr('Turn off "still to do" reminders')
                      : tr('Turn on "still to do" reminders'),
                ),
              ),
            ],
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
          Row(
            children: [
              _HardDayBar(day: today, hard: hard),
              const Spacer(),
              TextButton.icon(
                onPressed: () => showFeelSheet(context, ref),
                icon: const Icon(Icons.healing, size: 18),
                label: Text(tr('I feel…')),
              ),
            ],
          ),
          if (hard != null) _HardDayPanel(day: today, hard: hard),
          const _FreshStartPanel(),
          const _TodayPanel(),
          const _ReviewPanel(),
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
          TasksPanel(onOpen: () => context.push(HabitsRoutes.tasks)),
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

/// "Hard day?" — opens the reason picker (hidden once today is a hard day).
class _HardDayBar extends ConsumerWidget {
  const _HardDayBar({required this.day, this.hard});

  final String day;
  final HardDay? hard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (hard != null) return const SizedBox.shrink();
    final notifier = ref.read(habitsProvider.notifier);
    return TextButton.icon(
      onPressed: () async {
        final reason = await showModalBottomSheet<MissReason>(
          context: context,
          showDragHandle: true,
          builder: (sheet) => SafeArea(
            child: ListView(
              shrinkWrap: true,
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
    );
  }
}

/// Today is a hard day: tiny versions only, misses excused.
class _HardDayPanel extends ConsumerWidget {
  const _HardDayPanel({required this.day, required this.hard});

  final String day;
  final HardDay hard;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SystemPanel(
    glow: Colors.orangeAccent,
    title: tr('[SYSTEM] HARD DAY MODE'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr(
            '{reason}. Only the tiny versions today, and misses are excused. Showing up at all counts.',
            {'reason': reasonLabel(hard.reason)},
          ),
          style: const TextStyle(height: 1.45),
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            onPressed: () =>
                ref.read(habitsProvider.notifier).setHardDay(day, null),
            child: Text(tr('Turn off')),
          ),
        ),
      ],
    ),
  );
}

/// A natural new beginning (new week, Hijri month, Ramadan): a good moment
/// to restart a quest. Dismissed for the day.
class _FreshStartPanel extends ConsumerWidget {
  const _FreshStartPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(habitsProvider);
    final now = DateTime.now();
    final kind = freshStart(now);
    final today = habitDay(now);
    if (kind == null || s.flags['fresh'] == today) {
      return const SizedBox.shrink();
    }
    final h = Hijri.of(now);
    final label = switch (kind) {
      'Ramadan' => tr('Ramadan has started'),
      'new Hijri month' => tr('A new Hijri month: {month}', {
        'month': tr(Hijri.months[h.month - 1]),
      }),
      'new month' => tr('A new month'),
      _ => tr('A new week'),
    };
    return SystemPanel(
      glow: Colors.greenAccent,
      title: tr('[SYSTEM] FRESH START'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr(
              '{when}. New beginnings make change easier — a good moment to restart a quest that slipped, or begin a new one.',
              {'when': label},
            ),
            style: const TextStyle(height: 1.45),
          ),
          Row(
            children: [
              TextButton(
                onPressed: () => context.push(HabitsRoutes.create),
                child: Text(tr('New quest')),
              ),
              const Spacer(),
              TextButton(
                onPressed: () =>
                    ref.read(habitsProvider.notifier).setFlag('fresh', today),
                child: Text(tr('Dismiss')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// What's still open today across the app, and signals that look off —
/// with "Talk about today".
class _TodayPanel extends ConsumerWidget {
  const _TodayPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(habitsProvider);
    final notifier = ref.read(habitsProvider.notifier);
    final now = DateTime.now();
    final open = Nudges.open(
      AppSignals.read(ref.read(sharedPreferencesProvider), now: now),
      now,
      all: true,
    );
    final flags = notifier.todayFlags();
    if (open.isEmpty && flags.isEmpty) return const SizedBox.shrink();
    return SystemPanel(
      glow: flags.isEmpty ? habitsAccent : Colors.orangeAccent,
      title: tr('[SYSTEM] TODAY'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final f in flags)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '⚠ $f',
                style: const TextStyle(color: Colors.orangeAccent),
              ),
            ),
          if (open.isNotEmpty) ...[
            Text(
              tr('Still to do:'),
              style: const TextStyle(color: Colors.white60),
            ),
            for (final n in open) Text('• ${n.text}'),
          ],
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: () => context.push(HabitsRoutes.today),
              icon: const Icon(Icons.forum_outlined, size: 18),
              label: Text(tr('Talk about today')),
            ),
          ),
        ],
      ),
    );
  }
}

/// The System's weekly review and its experiment.
class _ReviewPanel extends ConsumerStatefulWidget {
  const _ReviewPanel();

  @override
  ConsumerState<_ReviewPanel> createState() => _ReviewPanelState();
}

class _ReviewPanelState extends ConsumerState<_ReviewPanel> {
  var _busy = false;
  String? _error;

  Future<void> _run() async {
    if (!ref.read(geminiClientProvider).isConfigured &&
        !await openGeminiKeySetup(context)) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(habitsProvider.notifier).weeklyReview();
    } on AiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(habitsProvider);
    final latest = s.reviews.firstOrNull;
    final recent =
        latest != null && DateTime.now().difference(latest.date).inDays < 7;
    if (!s.reviewDue && !recent) return const SizedBox.shrink();
    return SystemPanel(
      title: tr('[SYSTEM] WEEKLY REVIEW'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (recent) ...[
            SimpleMarkdown(latest.text),
            if (latest.experiment.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                tr('Experiment: {x}', {'x': latest.experiment}),
                style: const TextStyle(
                  color: habitsAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: () async {
                    await ref
                        .read(habitsProvider.notifier)
                        .addTask(latest.experiment, fromSystem: true);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(tr('Added to your to-do.'))),
                      );
                    }
                  },
                  child: Text(tr('Add to to-do')),
                ),
              ),
            ],
          ] else ...[
            Text(
              tr(
                'A week of data is in. The System can look at it all and suggest one experiment.',
              ),
            ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: _busy
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : TextButton(
                      onPressed: _run,
                      child: Text(tr('Get my weekly review')),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
