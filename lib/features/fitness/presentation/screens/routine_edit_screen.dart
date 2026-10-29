import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/dialogs.dart';
import '../../domain/entities/fitness_entities.dart';
import '../../fitness_routes.dart';
import '../providers/fitness_providers.dart';
import '../widgets/exercise_media.dart';
import '../widgets/fitness_sheets.dart';

/// Edit a workout: name, training days, exercises and their targets.
class RoutineEditScreen extends ConsumerWidget {
  const RoutineEditScreen({super.key, required this.routineId});

  final String routineId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routine = ref
        .watch(routinesProvider)
        .where((r) => r.id == routineId)
        .firstOrNull;
    if (routine == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This workout was deleted.')),
      );
    }
    final library = ref.watch(exerciseLibraryProvider).value ?? const {};
    final notifier = ref.read(routinesProvider.notifier);
    void save(Routine r) => notifier.update(r);

    return Scaffold(
      appBar: AppBar(
        title: Text(routine.name),
        actions: [
          IconButton(
            tooltip: 'Rename',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final name = await showTextInputDialog(
                context,
                title: 'Workout name',
                initialValue: routine.name,
              );
              if (name != null && name.trim().isNotEmpty) {
                save(routine.copyWith(name: name.trim()));
              }
            },
          ),
          IconButton(
            tooltip: 'Delete workout',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final ok = await showConfirmDialog(
                context,
                title: 'Delete ${routine.name}?',
                message: 'Your workout history stays.',
              );
              if (ok && context.mounted) {
                context.pop();
                await notifier.remove(routine.id);
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        shape: const StadiumBorder(),
        backgroundColor: fitnessAccent,
        foregroundColor: Colors.black,
        onPressed: () async {
          final id = await context.push<String>(FitnessRoutes.pickExercise);
          if (id != null) {
            save(
              routine.copyWith(
                items: [
                  ...routine.items,
                  PlanItem(exerciseId: id),
                ],
              ),
            );
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Exercise'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Training days',
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final d in weekOrder)
                      FilterChip(
                        label: Text(weekdayShort[d]!),
                        selected: routine.weekdays.contains(d),
                        selectedColor: fitnessAccent.withValues(alpha: 0.35),
                        showCheckmark: false,
                        onSelected: (v) => save(
                          routine.copyWith(
                            weekdays: v
                                ? {...routine.weekdays, d}
                                : ({...routine.weekdays}..remove(d)),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: routine.items.isEmpty
                ? const Center(
                    child: Text(
                      'No exercises yet. Tap "Exercise" to add one.',
                      style: TextStyle(color: Colors.white60),
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: routine.items.length,
                    onReorder: (from, to) {
                      final items = [...routine.items];
                      final item = items.removeAt(from);
                      items.insert(to > from ? to - 1 : to, item);
                      save(routine.copyWith(items: items));
                    },
                    itemBuilder: (context, i) {
                      final item = routine.items[i];
                      final e = library[item.exerciseId];
                      return ListTile(
                        key: ValueKey('$i-${item.exerciseId}'),
                        leading: e == null
                            ? const Icon(Icons.fitness_center)
                            : ExerciseThumb(exercise: e, size: 48),
                        title: Text(
                          e?.name ?? item.exerciseId.replaceAll('_', ' '),
                        ),
                        subtitle: Text(
                          '${item.target} · rest ${item.restSeconds}s',
                          style: const TextStyle(color: Colors.white60),
                        ),
                        trailing: const Icon(Icons.drag_handle),
                        onTap: () async {
                          final updated = await _editItem(context, item, e);
                          if (updated == null) return;
                          final items = [...routine.items];
                          if (updated == _remove) {
                            items.removeAt(i);
                          } else {
                            items[i] = updated;
                          }
                          save(routine.copyWith(items: items));
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

const _remove = PlanItem(exerciseId: '__remove__');

Future<PlanItem?> _editItem(
  BuildContext context,
  PlanItem item,
  Exercise? exercise,
) {
  var current = item;
  return showModalBottomSheet<PlanItem>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) {
        Widget stepper(
          String label,
          int value,
          ValueChanged<int> onChanged, {
          int step = 1,
          int min = 1,
          String suffix = '',
        }) => Row(
          children: [
            Expanded(child: Text(label)),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: value - step >= min
                  ? () => setSheet(() => onChanged(value - step))
                  : null,
            ),
            SizedBox(
              width: 56,
              child: Text(
                '$value$suffix',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => setSheet(() => onChanged(value + step)),
            ),
          ],
        );

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  exercise?.name ?? item.exerciseId,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (item.note != null)
                  Text(
                    item.note!,
                    style: const TextStyle(color: Colors.white60),
                  ),
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Reps')),
                    ButtonSegment(value: true, label: Text('Time')),
                  ],
                  selected: {current.timed},
                  onSelectionChanged: (v) => setSheet(
                    () => current = v.first
                        ? current.copyWith(seconds: 30)
                        : current.copyWith(clearSeconds: true),
                  ),
                ),
                const SizedBox(height: 8),
                stepper(
                  'Sets',
                  current.sets,
                  (v) => current = current.copyWith(sets: v),
                ),
                if (current.timed)
                  stepper(
                    'Seconds',
                    current.seconds!,
                    (v) => current = current.copyWith(seconds: v),
                    step: 5,
                    min: 5,
                    suffix: 's',
                  )
                else ...[
                  stepper(
                    'Reps from',
                    current.repsMin,
                    (v) => current = current.copyWith(
                      repsMin: v,
                      repsMax: v > current.repsMax ? v : null,
                    ),
                  ),
                  stepper(
                    'Reps up to',
                    current.repsMax,
                    (v) => current = current.copyWith(repsMax: v),
                    min: current.repsMin,
                  ),
                ],
                stepper(
                  'Rest',
                  current.restSeconds,
                  (v) => current = current.copyWith(restSeconds: v),
                  step: 15,
                  min: 15,
                  suffix: 's',
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Each side (per leg / arm)'),
                  value: current.perSide,
                  onChanged: (v) =>
                      setSheet(() => current = current.copyWith(perSide: v)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => Navigator.pop(context, _remove),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remove'),
                    ),
                    const Spacer(),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: fitnessAccent,
                        foregroundColor: Colors.black,
                      ),
                      onPressed: () => Navigator.pop(context, current),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
