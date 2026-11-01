import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/i18n.dart';
import '../../domain/default_plan.dart';
import '../../domain/entities/fitness_entities.dart';
import '../../fitness_routes.dart';
import '../providers/fitness_providers.dart';
import 'exercise_media.dart';

/// What the options sheet can return besides navigating on its own.
enum ExerciseAction { edit, remove }

/// Similar exercises for [item] in [routine]: the other options of its plan
/// slot, or (for exercises added by hand) home exercises for the same muscle.
List<String> similarExercises(
  Routine routine,
  PlanItem item,
  Map<String, Exercise> library,
) {
  final fromPlan = alternativesFor(routine.id, item.exerciseId);
  if (fromPlan.isNotEmpty) return fromPlan;
  final muscle = library[item.exerciseId]?.primaryMuscles.firstOrNull;
  if (muscle == null) return const [];
  const home = {null, 'body only', 'dumbbell', 'kettlebells'};
  final noBar = RegExp(r'pull|chin|hanging|muscle.?up', caseSensitive: false);
  return [
    for (final e in library.values)
      if (e.id != item.exerciseId &&
          e.primaryMuscles.contains(muscle) &&
          home.contains(e.equipment) &&
          e.level != 'expert' &&
          !noBar.hasMatch(e.name))
        e.id,
  ].take(8).toList();
}

/// Tapping an exercise of a workout: how to do it, swap it for a similar one,
/// and (when [canEdit]) change its sets / remove it.
Future<ExerciseAction?> showExerciseOptions(
  BuildContext context,
  WidgetRef ref, {
  required Routine routine,
  required int index,
  bool canEdit = false,
}) {
  final item = routine.items[index];
  final library = ref.read(exerciseLibraryProvider).value ?? const {};
  final exercise = library[item.exerciseId];
  final name = exercise?.name ?? item.exerciseId.replaceAll('_', ' ');
  final similar = similarExercises(routine, item, library);

  return showModalBottomSheet<ExerciseAction>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: exercise == null
                ? const Icon(Icons.fitness_center)
                : ExerciseThumb(exercise: exercise, size: 48),
            title: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(item.target),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: Text(tr('How to do it')),
            subtitle: Text(tr('Steps, pictures and muscles worked')),
            onTap: () {
              Navigator.pop(sheet);
              context.push(FitnessRoutes.exercise(item.exerciseId));
            },
          ),
          if (similar.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: Text(tr('Swap for a similar exercise')),
              subtitle: Text(
                tr('{n} options for the same muscles', {'n': similar.length}),
              ),
              onTap: () async {
                Navigator.pop(sheet);
                final picked = await _pickSimilar(context, similar, library);
                if (picked != null) {
                  await ref
                      .read(routinesProvider.notifier)
                      .swap(routine.id, index, picked);
                }
              },
            ),
          if (canEdit) ...[
            ListTile(
              leading: const Icon(Icons.tune),
              title: Text(tr('Sets, reps & rest')),
              onTap: () => Navigator.pop(sheet, ExerciseAction.edit),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(tr('Remove from this workout')),
              onTap: () => Navigator.pop(sheet, ExerciseAction.remove),
            ),
          ] else
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(tr('Edit this workout')),
              onTap: () {
                Navigator.pop(sheet);
                context.push(FitnessRoutes.routine(routine.id));
              },
            ),
        ],
      ),
    ),
  );
}

Future<String?> _pickSimilar(
  BuildContext context,
  List<String> ids,
  Map<String, Exercise> library,
) => showModalBottomSheet<String>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (sheet) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              tr('Swap for'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final id in ids)
            ListTile(
              leading: library[id] == null
                  ? const Icon(Icons.fitness_center)
                  : ExerciseThumb(exercise: library[id]!, size: 48),
              title: Text(library[id]?.name ?? id.replaceAll('_', ' ')),
              subtitle: library[id] == null
                  ? null
                  : Text(
                      [
                        library[id]!.equipmentLabel,
                        library[id]!.primaryMuscles
                            .map(Muscle.label)
                            .join(', '),
                      ].join(' · '),
                    ),
              trailing: IconButton(
                tooltip: tr('How to do it'),
                icon: const Icon(Icons.info_outline),
                onPressed: () => context.push(FitnessRoutes.exercise(id)),
              ),
              onTap: () => Navigator.pop(sheet, id),
            ),
        ],
      ),
    ),
  ),
);
