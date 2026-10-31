import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/widgets/dialogs.dart';
import '../../domain/entities/fitness_entities.dart';
import '../../domain/progress_math.dart';
import '../../fitness_routes.dart';
import '../providers/fitness_providers.dart';
import '../widgets/body_diagram.dart';
import '../widgets/fitness_sheets.dart';
import '../widgets/line_chart.dart';
import 'exercise_list_screen.dart';

/// Today · Plan · Exercises · Progress.
class FitnessHomeScreen extends ConsumerStatefulWidget {
  const FitnessHomeScreen({super.key});

  @override
  ConsumerState<FitnessHomeScreen> createState() => _FitnessHomeScreenState();
}

class _FitnessHomeScreenState extends ConsumerState<FitnessHomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final titles = [tr('Today'), tr('Plan'), tr('Exercises'), tr('Progress')];
    return Scaffold(
      appBar: _tab == 2
          ? null
          : AppBar(
              title: Text(titles[_tab]),
              actions: [
                IconButton(
                  tooltip: tr('Profile, goal & reminders'),
                  icon: const Icon(Icons.person_outline),
                  onPressed: () => showProfileSheet(context, ref),
                ),
                if (_tab == 1)
                  PopupMenuButton<String>(
                    onSelected: (_) async {
                      final ok = await showConfirmDialog(
                        context,
                        title: tr('Reset to the starter plan?'),
                        message: tr(
                          'Your routines are replaced by the 4-day starter plan. Workout history stays.',
                        ),
                        confirmLabel: tr('Reset'),
                      );
                      if (ok) {
                        await ref
                            .read(routinesProvider.notifier)
                            .resetToDefault();
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'reset',
                        child: Text(tr('Reset to starter plan')),
                      ),
                    ],
                  ),
              ],
            ),
      body: switch (_tab) {
        0 => const _TodayTab(),
        1 => const _PlanTab(),
        2 => const ExerciseListScreen(embedded: true),
        _ => const _ProgressTab(),
      },
      floatingActionButton: _tab == 1
          ? FloatingActionButton.extended(
              shape: const StadiumBorder(),
              backgroundColor: fitnessAccent,
              foregroundColor: Colors.black,
              onPressed: () async {
                final r = await ref
                    .read(routinesProvider.notifier)
                    .add('New workout');
                if (context.mounted) context.push(FitnessRoutes.routine(r.id));
              },
              icon: const Icon(Icons.add),
              label: Text(tr('Workout')),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: tr('Today'),
          ),
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note),
            label: tr('Plan'),
          ),
          NavigationDestination(
            icon: Icon(Icons.fitness_center_outlined),
            selectedIcon: Icon(Icons.fitness_center),
            label: tr('Exercises'),
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart),
            label: tr('Progress'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Today
// ---------------------------------------------------------------------------

class _TodayTab extends ConsumerWidget {
  const _TodayTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeWorkoutProvider);
    final next = ref.watch(nextRoutineProvider);
    final sessions = ref.watch(sessionsProvider);
    final routines = ref.watch(routinesProvider);
    final library = ref.watch(exerciseLibraryProvider).value ?? const {};
    final now = DateTime.now();
    final weekStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: (now.weekday - DateTime.saturday) % 7));
    final thisWeek = sessions.where((s) => !s.startedAt.isBefore(weekStart));
    final planned = {for (final r in routines) ...r.weekdays}.length;
    final streak = ProgressMath.weekStreak(
      sessions.map((s) => s.startedAt),
      now,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        if (active != null)
          Card(
            color: fitnessAccent.withValues(alpha: 0.15),
            child: ListTile(
              leading: const Icon(Icons.timer, color: fitnessAccent),
              title: Text(
                tr('{routineName} in progress', {
                  'routineName': active.routineName,
                }),
              ),
              subtitle: Text(
                '${active.doneSets}/${active.totalSets} sets · started '
                '${DateFormat('HH:mm').format(active.startedAt)}',
              ),
              trailing: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: fitnessAccent,
                  foregroundColor: Colors.black,
                ),
                onPressed: () => context.push(FitnessRoutes.workout),
                child: Text(tr('Resume')),
              ),
            ),
          )
        else if (next != null)
          _NextWorkoutCard(
            routine: next.routine,
            inDays: next.inDays,
            library: library,
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            _Stat(
              label: tr('This week'),
              value: '${thisWeek.length}${planned > 0 ? '/$planned' : ''}',
            ),
            _Stat(label: tr('Week streak'), value: '$streak'),
            _Stat(label: tr('Workouts'), value: '${sessions.length}'),
          ],
        ),
        const SizedBox(height: 12),
        const _WeightCard(),
        if (active == null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _chooseWorkout(context, ref),
            icon: const Icon(Icons.play_arrow),
            label: Text(tr('Start a different workout')),
          ),
        ],
        if (sessions.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            tr('Recent workouts'),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          for (final s in sessions.take(4)) _SessionTile(session: s),
        ],
      ],
    );
  }

  Future<void> _chooseWorkout(BuildContext context, WidgetRef ref) async {
    final routines = ref.read(routinesProvider);
    final choice = await showModalBottomSheet<Object>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final r in routines)
              ListTile(
                leading: const Icon(Icons.event_note),
                title: Text(r.name),
                subtitle: Text('${r.items.length} exercises'),
                onTap: () => Navigator.pop(context, r),
              ),
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: Text(tr('Free workout')),
              subtitle: Text(tr('Add exercises as you go')),
              onTap: () => Navigator.pop(context, 'free'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    ref
        .read(activeWorkoutProvider.notifier)
        .start(choice is Routine ? choice : null);
    context.push(FitnessRoutes.workout);
  }
}

class _NextWorkoutCard extends ConsumerWidget {
  const _NextWorkoutCard({
    required this.routine,
    required this.inDays,
    required this.library,
  });

  final Routine routine;
  final int inDays;
  final Map<String, Exercise> library;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final when = inDays == 0
        ? tr('Today')
        : inDays == 1
        ? tr('Tomorrow')
        : DateFormat('EEEE').format(DateTime.now().add(Duration(days: inDays)));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              when,
              style: const TextStyle(color: fitnessAccent, fontSize: 13),
            ),
            Text(
              routine.name,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final item in routine.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    const Icon(Icons.circle, size: 6, color: Colors.white38),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        library[item.exerciseId]?.name ??
                            item.exerciseId.replaceAll('_', ' '),
                      ),
                    ),
                    Text(
                      item.target,
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: fitnessAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: routine.items.isEmpty
                    ? null
                    : () {
                        ref.read(activeWorkoutProvider.notifier).start(routine);
                        context.push(FitnessRoutes.workout);
                      },
                icon: const Icon(Icons.play_arrow),
                label: Text(
                  inDays == 0 ? tr('Start workout') : tr('Start now anyway'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Card(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.white60),
            ),
          ],
        ),
      ),
    ),
  );
}

class _WeightCard extends ConsumerWidget {
  const _WeightCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(fitnessProfileProvider);
    ref.watch(bodyLogProvider);
    final latest =
        ref.read(bodyLogProvider.notifier).latestWeight ??
        profile.startWeightKg;
    final lost = profile.startWeightKg - latest;
    final toGo = latest - profile.goalWeightKg;
    final total = profile.startWeightKg - profile.goalWeightKg;
    final fraction = total <= 0 ? 0.0 : (lost / total).clamp(0.0, 1.0);
    final bmi = ProgressMath.bmi(latest, profile.heightCm);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '${fmtKg(latest)} kg',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 10),
                if (lost.abs() >= 0.1)
                  Text(
                    lost > 0
                        ? tr('−{0} kg', {'0': fmtKg(lost)})
                        : tr('+{0} kg', {'0': fmtKg(-lost)}),
                    style: TextStyle(
                      color: lost > 0 ? fitnessAccent : Colors.orangeAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: () => showBodyLogSheet(context, ref),
                  icon: const Icon(Icons.monitor_weight_outlined, size: 18),
                  label: Text(tr('Log')),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
                color: fitnessAccent,
                backgroundColor: Colors.white12,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              toGo > 0
                  ? tr('{0} kg to your goal of {1} kg · BMI {2} ({3})', {
                      '0': fmtKg(toGo),
                      '1': fmtKg(profile.goalWeightKg),
                      '2': bmi.toStringAsFixed(1),
                      '3': ProgressMath.bmiLabel(bmi),
                    })
                  : tr('Goal reached! 🎉 BMI {0}', {
                      '0': bmi.toStringAsFixed(1),
                    }),
              style: const TextStyle(fontSize: 12.5, color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionTile extends ConsumerWidget {
  const _SessionTile({required this.session});

  final WorkoutSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: CircleAvatar(
      backgroundColor: fitnessAccent.withValues(alpha: 0.18),
      child: const Icon(Icons.check, color: fitnessAccent),
    ),
    title: Text(session.routineName ?? tr('Workout')),
    subtitle: Text(
      '${DateFormat('EEE d MMM').format(session.startedAt)} · '
      '${fmtDuration(session.duration)} · ${plural(session.setCount, 'set')}',
    ),
    onTap: () => showSessionSheet(context, ref, session),
  );
}

// ---------------------------------------------------------------------------
// Plan
// ---------------------------------------------------------------------------

class _PlanTab extends ConsumerWidget {
  const _PlanTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routines = ref.watch(routinesProvider);
    final library = ref.watch(exerciseLibraryProvider).value ?? const {};
    if (routines.isEmpty) {
      return Center(
        child: Text(
          tr(
            'No workouts yet. Tap "Workout" to create one,\nor reset to the starter plan from the ⋮ menu.',
          ),
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white60),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            tr(
              'Add weight (or reps) once you hit the top of the rep range on every set — the workout screen tells you when.',
            ),
            style: TextStyle(color: Colors.white60, fontSize: 13),
          ),
        ),
        for (final r in routines)
          Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => context.push(FitnessRoutes.routine(r.id)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            r.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        for (final d in weekOrder)
                          if (r.weekdays.contains(d))
                            Container(
                              margin: const EdgeInsets.only(left: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: fitnessAccent.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                tr(weekdayShort[d]!),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      r.items.isEmpty
                          ? tr('No exercises yet')
                          : r.items
                                .map(
                                  (i) =>
                                      library[i.exerciseId]?.name ??
                                      i.exerciseId.replaceAll('_', ' '),
                                )
                                .join(' · '),
                      style: const TextStyle(color: Colors.white60),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Progress
// ---------------------------------------------------------------------------

/// 0–1 per muscle: sets in the last 7 days relative to the most-trained one.
Map<String, double> _weeklyMuscles(
  List<WorkoutSession> sessions,
  Map<String, Exercise> library,
) {
  final since = DateTime.now().subtract(const Duration(days: 7));
  final sets = <String, double>{};
  for (final s in sessions.where((s) => s.startedAt.isAfter(since))) {
    for (final log in s.exercises) {
      final e = library[log.exerciseId];
      if (e == null) continue;
      for (final m in e.primaryMuscles) {
        sets[m] = (sets[m] ?? 0) + log.sets.length;
      }
      for (final m in e.secondaryMuscles) {
        sets[m] = (sets[m] ?? 0) + log.sets.length / 2;
      }
    }
  }
  if (sets.isEmpty) return const {};
  final most = sets.values.reduce((a, b) => a > b ? a : b);
  return {for (final e in sets.entries) e.key: 0.2 + 0.8 * e.value / most};
}

class _ProgressTab extends ConsumerWidget {
  const _ProgressTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(fitnessProfileProvider);
    final body = ref.watch(bodyLogProvider);
    final sessions = ref.watch(sessionsProvider);
    final library = ref.watch(exerciseLibraryProvider).value ?? const {};
    final weights = [
      for (final e in body)
        if (e.weightKg != null) (x: e.date, y: e.weightKg!),
    ];

    // Sessions per week, last 8 weeks (week starts Saturday).
    final now = DateTime.now();
    final thisWeek = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: (now.weekday - DateTime.saturday) % 7));
    final weekly = [
      for (var i = 7; i >= 0; i--)
        sessions.where((s) {
          final start = thisWeek.subtract(Duration(days: 7 * i));
          return !s.startedAt.isBefore(start) &&
              s.startedAt.isBefore(start.add(const Duration(days: 7)));
        }).length,
    ];

    // Personal bests for exercises done at least once.
    final doneIds = {
      for (final s in sessions)
        for (final e in s.exercises) e.exerciseId,
    };
    final bests = [
      for (final id in doneIds)
        if (ProgressMath.best(id, sessions) case final pb?) (id: id, pb: pb),
    ]..sort((a, b) => b.pb.date.compareTo(a.pb.date));

    final measured = [
      for (final k in BodyEntry.measurements)
        if (body.any((e) => e.measurement(k) != null)) k,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                tr('Body weight'),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton.icon(
              onPressed: () => showBodyLogSheet(context, ref),
              icon: const Icon(Icons.add, size: 18),
              label: Text(tr('Log')),
            ),
          ],
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
            child: ProgressLineChart(
              points: [
                if (weights.isEmpty || weights.first.x.isAfter(now))
                  (x: now, y: profile.startWeightKg),
                ...weights,
              ],
              goal: profile.goalWeightKg,
              unit: ' kg',
            ),
          ),
        ),
        if (measured.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            tr('Measurements'),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          Card(
            child: Column(
              children: [
                for (final k in measured)
                  Builder(
                    builder: (context) {
                      final values = [for (final e in body) ?e.measurement(k)];
                      final change = values.last - values.first;
                      return ListTile(
                        dense: true,
                        title: Text(k[0].toUpperCase() + k.substring(1)),
                        trailing: Text(
                          '${fmtKg(values.last)} cm'
                          '${values.length > 1 ? '  (${change <= 0 ? '' : '+'}${fmtKg(change)})' : ''}',
                          style: TextStyle(
                            color: change < 0 ? fitnessAccent : null,
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          tr('Muscles trained this week'),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        Text(
          tr(
            'Sets in the last 7 days (helping muscles count half). Grey = not trained yet.',
          ),
          style: TextStyle(fontSize: 12.5, color: Colors.white60),
        ),
        const SizedBox(height: 10),
        BodyDiagram(intensity: _weeklyMuscles(sessions, library), height: 240),
        const SizedBox(height: 16),
        Text(
          tr('Workouts per week'),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 90,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (i, n) in weekly.indexed)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('$n', style: const TextStyle(fontSize: 11)),
                      const SizedBox(height: 2),
                      Container(
                        height: 8.0 + n * 14,
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(
                          color: i == weekly.length - 1
                              ? fitnessAccent
                              : fitnessAccent.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          tr('Personal bests'),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        if (bests.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              tr('Finish a workout to see your records here.'),
              style: TextStyle(color: Colors.white54),
            ),
          ),
        for (final b in bests)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.emoji_events_outlined),
            title: Text(library[b.id]?.name ?? b.id.replaceAll('_', ' ')),
            subtitle: Text(DateFormat('d MMM y').format(b.pb.date)),
            trailing: Text(
              b.pb.label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            onTap: () => context.push(FitnessRoutes.exercise(b.id)),
          ),
        if (sessions.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            tr('History'),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          for (final s in sessions) _SessionTile(session: s),
        ],
      ],
    );
  }
}
