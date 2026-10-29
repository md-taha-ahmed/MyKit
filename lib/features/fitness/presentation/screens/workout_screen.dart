import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/dialogs.dart';
import '../../domain/entities/fitness_entities.dart';
import '../../domain/progress_math.dart';
import '../../fitness_routes.dart';
import '../providers/fitness_providers.dart';
import '../widgets/exercise_media.dart';
import '../widgets/fitness_sheets.dart';

/// The workout in progress: one exercise at a time, sets with weight and
/// reps (pre-filled from last time), rest timer between sets.
class WorkoutScreen extends ConsumerStatefulWidget {
  const WorkoutScreen({super.key});

  @override
  ConsumerState<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends ConsumerState<WorkoutScreen> {
  Timer? _ticker;

  // Rest countdown.
  DateTime? _restEnds;
  int _restTotal = 0;

  // Hold timer for timed sets.
  ({int exercise, int set})? _holding;
  DateTime? _holdStarted;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    final ends = _restEnds;
    if (ends != null && !DateTime.now().isBefore(ends)) {
      _endRest(alert: true);
    }
    final hold = _holding;
    if (hold != null) {
      final w = ref.read(activeWorkoutProvider);
      final target = w?.exercises[hold.exercise].item.seconds ?? 0;
      if (_holdSeconds >= target) _stopHold(alert: true);
    }
    setState(() {});
  }

  int get _holdSeconds => _holdStarted == null
      ? 0
      : DateTime.now().difference(_holdStarted!).inSeconds;

  void _startRest(int seconds, String next) {
    if (seconds <= 0) return;
    setState(() {
      _restTotal = seconds;
      _restEnds = DateTime.now().add(Duration(seconds: seconds));
    });
    ref
        .read(fitnessNotificationsProvider)
        .scheduleRestEnd(Duration(seconds: seconds), next);
  }

  void _endRest({bool alert = false}) {
    if (_restEnds == null) return;
    setState(() => _restEnds = null);
    ref.read(fitnessNotificationsProvider).cancelRest();
    if (alert) {
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
    }
  }

  void _addRest(int seconds) {
    final ends = _restEnds;
    if (ends == null) return;
    final next = ends.add(Duration(seconds: seconds));
    setState(() {
      _restEnds = next;
      _restTotal += seconds;
    });
    ref
        .read(fitnessNotificationsProvider)
        .scheduleRestEnd(next.difference(DateTime.now()), 'Next set');
  }

  void _startHold(int exercise, int set) {
    _endRest();
    setState(() {
      _holding = (exercise: exercise, set: set);
      _holdStarted = DateTime.now();
    });
  }

  void _stopHold({bool alert = false}) {
    final hold = _holding;
    if (hold == null) return;
    final secs = _holdSeconds;
    setState(() {
      _holding = null;
      _holdStarted = null;
    });
    final w = ref.read(activeWorkoutProvider);
    if (w == null) return;
    final set = w.exercises[hold.exercise].sets[hold.set];
    _complete(hold.exercise, hold.set, set.copyWith(seconds: secs));
    if (alert) {
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
    }
  }

  /// Marks a set done and starts the rest before the next one.
  void _complete(int ex, int set, ActiveSet value) {
    final notifier = ref.read(activeWorkoutProvider.notifier);
    notifier.updateSet(ex, set, value.copyWith(done: true));
    HapticFeedback.lightImpact();
    final w = ref.read(activeWorkoutProvider)!;
    final exercise = w.exercises[ex];
    final lastSet = set == exercise.sets.length - 1;
    final lastExercise = ex == w.exercises.length - 1;
    if (lastSet && lastExercise) return;
    final library = ref.read(exerciseLibraryProvider).value ?? const {};
    final nextName = lastSet
        ? library[w.exercises[ex + 1].item.exerciseId]?.name ?? 'Next exercise'
        : '${library[exercise.item.exerciseId]?.name ?? 'Next'} — set ${set + 2}';
    _startRest(exercise.item.restSeconds, nextName);
    if (lastSet) notifier.goTo(ex + 1);
  }

  Future<void> _finish() async {
    final w = ref.read(activeWorkoutProvider);
    if (w == null) return;
    if (w.doneSets < w.totalSets) {
      final ok = await showConfirmDialog(
        context,
        title: 'Finish workout?',
        message:
            '${w.doneSets} of ${w.totalSets} sets done. Unticked sets '
            'aren\'t saved.',
        confirmLabel: 'Finish',
      );
      if (!ok) return;
    }
    _endRest();
    final before = ref.read(sessionsProvider);
    final session = await ref.read(activeWorkoutProvider.notifier).finish();
    if (!mounted) return;
    if (session == null) {
      context.pop();
      return;
    }
    final library = ref.read(exerciseLibraryProvider).value ?? const {};
    final records = [
      for (final log in session.exercises)
        if (ProgressMath.best(log.exerciseId, [session]) case final now?)
          if ((ProgressMath.best(log.exerciseId, before)?.score ?? 0) <
              now.score)
            '${library[log.exerciseId]?.name ?? log.exerciseId}: ${now.label}',
    ];
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Workout done 💪'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${fmtDuration(session.duration)} · ${plural(session.setCount, 'set')}'
              '${session.volume > 0 ? ' · ${fmtKg(session.volume)} kg lifted' : ''}',
            ),
            if (records.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'New personal bests',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              for (final r in records) Text('🏆 $r'),
            ],
            const SizedBox(height: 12),
            const Text(
              'Log your weight once or twice a week, at the same time of '
              'day, to see the trend.',
              style: TextStyle(color: Colors.white60, fontSize: 13),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final w = ref.watch(activeWorkoutProvider);
    final library = ref.watch(exerciseLibraryProvider).value ?? const {};
    if (w == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(
          child: Icon(Icons.check_circle, color: fitnessAccent, size: 72),
        ),
      );
    }
    final elapsed = DateTime.now().difference(w.startedAt);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(w.routineName ?? 'Workout'),
            Text(
              '${_clock(elapsed)} · ${w.doneSets}/${w.totalSets} sets',
              style: const TextStyle(fontSize: 12.5, color: Colors.white60),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'add') {
                final id = await context.push<String>(
                  FitnessRoutes.pickExercise,
                );
                if (id != null) {
                  ref.read(activeWorkoutProvider.notifier).addExercise(id);
                }
              } else if (v == 'discard') {
                final ok = await showConfirmDialog(
                  context,
                  title: 'Discard this workout?',
                  message: 'Nothing from it will be saved.',
                  confirmLabel: 'Discard',
                );
                if (ok) {
                  _endRest();
                  await ref.read(activeWorkoutProvider.notifier).discard();
                  if (context.mounted) context.pop();
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'add', child: Text('Add exercise')),
              PopupMenuItem(value: 'discard', child: Text('Discard workout')),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: fitnessAccent,
                foregroundColor: Colors.black,
              ),
              onPressed: _finish,
              child: const Text('Finish'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: w.totalSets == 0 ? 0 : w.doneSets / w.totalSets,
            color: fitnessAccent,
            backgroundColor: Colors.white10,
            minHeight: 3,
          ),
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              children: [
                for (final (i, e) in w.exercises.indexed)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      avatar: e.sets.every((s) => s.done)
                          ? const Icon(Icons.check, size: 16)
                          : null,
                      label: Text(
                        library[e.item.exerciseId]?.name ??
                            e.item.exerciseId.replaceAll('_', ' '),
                        overflow: TextOverflow.ellipsis,
                      ),
                      showCheckmark: false,
                      selected: i == w.current,
                      selectedColor: fitnessAccent.withValues(alpha: 0.3),
                      onSelected: (_) =>
                          ref.read(activeWorkoutProvider.notifier).goTo(i),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: w.exercises.isEmpty
                ? Center(
                    child: FilledButton.icon(
                      onPressed: () async {
                        final id = await context.push<String>(
                          FitnessRoutes.pickExercise,
                        );
                        if (id != null) {
                          ref
                              .read(activeWorkoutProvider.notifier)
                              .addExercise(id);
                        }
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add an exercise'),
                    ),
                  )
                : _ExercisePage(
                    key: ValueKey(w.current),
                    index: w.current,
                    exercise: w.exercises[w.current],
                    info: library[w.exercises[w.current].item.exerciseId],
                    holding: _holding,
                    holdSeconds: _holdSeconds,
                    onComplete: _complete,
                    onStartHold: _startHold,
                    onStopHold: () => _stopHold(),
                    isLast: w.current == w.exercises.length - 1,
                  ),
          ),
          if (_restEnds != null) _restBar(),
        ],
      ),
    );
  }

  Widget _restBar() {
    final left = _restEnds!.difference(DateTime.now()).inSeconds.clamp(0, 9999);
    return SafeArea(
      top: false,
      child: Container(
        color: const Color(0xFF1B2A1F),
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 44,
              child: CircularProgressIndicator(
                value: _restTotal == 0 ? 0 : left / _restTotal,
                color: fitnessAccent,
                backgroundColor: Colors.white12,
                strokeWidth: 4,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Rest', style: TextStyle(color: Colors.white60)),
                  Text(
                    _clock(Duration(seconds: left)),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => _addRest(15),
              child: const Text('+15s'),
            ),
            TextButton(onPressed: _endRest, child: const Text('Skip')),
          ],
        ),
      ),
    );
  }

  static String _clock(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }
}

class _ExercisePage extends ConsumerWidget {
  const _ExercisePage({
    super.key,
    required this.index,
    required this.exercise,
    required this.info,
    required this.holding,
    required this.holdSeconds,
    required this.onComplete,
    required this.onStartHold,
    required this.onStopHold,
    required this.isLast,
  });

  final int index;
  final ActiveExercise exercise;
  final Exercise? info;
  final ({int exercise, int set})? holding;
  final int holdSeconds;
  final void Function(int ex, int set, ActiveSet value) onComplete;
  final void Function(int ex, int set) onStartHold;
  final VoidCallback onStopHold;
  final bool isLast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = exercise.item;
    final notifier = ref.read(activeWorkoutProvider.notifier);
    final sessions = ref.watch(sessionsProvider);
    final last = ProgressMath.lastSets(item.exerciseId, sessions);
    final ready = ProgressMath.readyToProgress(item, last);
    final weighted = info?.usesWeight ?? false;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        if (info != null)
          GestureDetector(
            onTap: () => context.push(FitnessRoutes.exercise(info!.id)),
            child: ExerciseMedia(exercise: info!, height: 170),
          ),
        const SizedBox(height: 10),
        Text(
          info?.name ?? item.exerciseId.replaceAll('_', ' '),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        Text(
          'Target ${item.target} · rest ${item.restSeconds}s',
          style: const TextStyle(color: fitnessAccent),
        ),
        if (item.note != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              item.note!,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        if (last != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Last time: ${[for (final s in last) s.seconds > 0
                    ? '${s.seconds}s'
                    : s.weightKg > 0
                    ? '${fmtKg(s.weightKg)}×${s.reps}'
                    : '${s.reps}'].join('  ')}',
              style: const TextStyle(color: Colors.white60),
            ),
          ),
        if (ready)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              item.timed
                  ? '⬆ You held the full time last session — add 5–10 seconds.'
                  : weighted
                  ? '⬆ You hit ${item.repsMax} reps on every set last time — '
                        'add 1–2 kg today.'
                  : '⬆ You hit ${item.repsMax} reps on every set — try a '
                        'harder variation or slow the tempo down.',
              style: const TextStyle(color: Colors.amber),
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            const SizedBox(width: 36, child: Text('Set')),
            if (weighted) const Expanded(child: Center(child: Text('kg'))),
            Expanded(
              child: Center(child: Text(item.timed ? 'seconds' : 'reps')),
            ),
            const SizedBox(width: 56),
          ],
        ),
        for (final (i, s) in exercise.sets.indexed)
          _SetRow(
            number: i + 1,
            set: s,
            weighted: weighted,
            timed: item.timed,
            holding:
                holding != null &&
                holding!.exercise == index &&
                holding!.set == i,
            holdSeconds: holdSeconds,
            onChanged: (v) => notifier.updateSet(index, i, v),
            onDone: () => s.done
                ? notifier.updateSet(index, i, s.copyWith(done: false))
                : item.timed
                ? (holding?.exercise == index && holding?.set == i
                      ? onStopHold()
                      : onStartHold(index, i))
                : onComplete(index, i, s),
            onRemove: exercise.sets.length > 1
                ? () => notifier.removeSet(index, i)
                : null,
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => notifier.addSet(index),
            icon: const Icon(Icons.add),
            label: const Text('Add set'),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (index > 0)
              OutlinedButton.icon(
                onPressed: () => notifier.goTo(index - 1),
                icon: const Icon(Icons.chevron_left),
                label: const Text('Previous'),
              ),
            const Spacer(),
            if (!isLast)
              FilledButton.tonalIcon(
                onPressed: () => notifier.goTo(index + 1),
                icon: const Icon(Icons.chevron_right),
                label: const Text('Next exercise'),
              ),
          ],
        ),
      ],
    );
  }
}

class _SetRow extends StatelessWidget {
  const _SetRow({
    required this.number,
    required this.set,
    required this.weighted,
    required this.timed,
    required this.holding,
    required this.holdSeconds,
    required this.onChanged,
    required this.onDone,
    this.onRemove,
  });

  final int number;
  final ActiveSet set;
  final bool weighted;
  final bool timed;
  final bool holding;
  final int holdSeconds;
  final ValueChanged<ActiveSet> onChanged;
  final VoidCallback onDone;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final done = set.done;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: done
            ? fitnessAccent.withValues(alpha: 0.12)
            : holding
            ? Colors.amber.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          GestureDetector(
            onLongPress: onRemove,
            child: SizedBox(
              width: 36,
              child: Center(
                child: Text(
                  '$number',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
          if (weighted)
            Expanded(
              child: _Stepper(
                value: set.weightKg,
                step: 1,
                decimals: true,
                onChanged: (v) => onChanged(set.copyWith(weightKg: v)),
              ),
            ),
          Expanded(
            child: timed
                ? Center(
                    child: Text(
                      holding ? '${holdSeconds}s' : '${set.seconds}s',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: holding ? Colors.amber : null,
                      ),
                    ),
                  )
                : _Stepper(
                    value: set.reps.toDouble(),
                    step: 1,
                    onChanged: (v) =>
                        onChanged(set.copyWith(reps: v.round().clamp(0, 999))),
                  ),
          ),
          SizedBox(
            width: 56,
            child: IconButton(
              iconSize: 30,
              tooltip: timed && !done
                  ? (holding ? 'Stop' : 'Start timer')
                  : done
                  ? 'Undo'
                  : 'Done',
              icon: Icon(
                done
                    ? Icons.check_circle
                    : timed
                    ? (holding ? Icons.stop_circle : Icons.play_circle)
                    : Icons.radio_button_unchecked,
                color: done
                    ? fitnessAccent
                    : holding
                    ? Colors.amber
                    : Colors.white60,
              ),
              onPressed: onDone,
            ),
          ),
        ],
      ),
    );
  }
}

/// − value + with tap-to-type.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.step,
    required this.onChanged,
    this.decimals = false,
  });

  final double value;
  final double step;
  final bool decimals;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = decimals ? fmtKg(value) : value.round().toString();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove, size: 18),
          onPressed: value - step >= 0 ? () => onChanged(value - step) : null,
        ),
        GestureDetector(
          onTap: () async {
            final typed = await showTextInputDialog(
              context,
              title: decimals ? 'Weight (kg)' : 'Reps',
              initialValue: text,
            );
            final v = double.tryParse((typed ?? '').replaceAll(',', '.'));
            if (v != null && v >= 0) onChanged(v);
          },
          child: SizedBox(
            width: 42,
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add, size: 18),
          onPressed: () => onChanged(value + step),
        ),
      ],
    );
  }
}
