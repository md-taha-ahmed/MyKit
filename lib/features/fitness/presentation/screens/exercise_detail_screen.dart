import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/widgets/dialogs.dart';
import '../../domain/entities/fitness_entities.dart';
import '../../domain/progress_math.dart';
import '../providers/fitness_providers.dart';
import '../widgets/body_diagram.dart';
import '../widgets/exercise_media.dart';
import '../widgets/fitness_sheets.dart';

/// Photos, muscles worked, how-to, and the user's own history.
class ExerciseDetailScreen extends ConsumerWidget {
  const ExerciseDetailScreen({super.key, required this.exerciseId});

  final String exerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(exerciseLibraryProvider);
    final exercise = library.value?[exerciseId];
    if (exercise == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: library.isLoading
              ? const CircularProgressIndicator()
              : Text(tr('Exercise not found.')),
        ),
      );
    }
    final sessions = ref.watch(sessionsProvider);
    final myPhotos = ref.watch(customImagesProvider)[exercise.id] ?? const [];
    final pb = ProgressMath.best(exercise.id, sessions);
    final history = [
      for (final s in sessions)
        for (final log in s.exercises)
          if (log.exerciseId == exercise.id)
            (date: s.startedAt, sets: log.sets),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(exercise.name),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'photo':
                  final picked = await FilePicker.pickFiles(
                    type: FileType.image,
                  );
                  final path = picked.firstOrNull?.path;
                  if (path != null) {
                    await ref
                        .read(customImagesProvider.notifier)
                        .add(exercise.id, path);
                  }
                case 'clear':
                  for (final p in myPhotos) {
                    await ref
                        .read(customImagesProvider.notifier)
                        .remove(exercise.id, p);
                  }
                case 'routine':
                  if (context.mounted) await _addToRoutine(context, ref);
                case 'delete':
                  final ok = await showConfirmDialog(
                    context,
                    title: tr('Delete {name}?', {'name': exercise.name}),
                    message: tr('Workout history for it stays.'),
                  );
                  if (ok && context.mounted) {
                    await ref
                        .read(customExercisesProvider.notifier)
                        .remove(exercise.id);
                    if (context.mounted) Navigator.pop(context);
                  }
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'routine',
                child: Text(tr('Add to a workout…')),
              ),
              PopupMenuItem(value: 'photo', child: Text(tr('Add my photo…'))),
              if (myPhotos.isNotEmpty)
                PopupMenuItem(
                  value: 'clear',
                  child: Text(tr('Remove my photos')),
                ),
              if (exercise.custom)
                PopupMenuItem(
                  value: 'delete',
                  child: Text(tr('Delete exercise')),
                ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          ExerciseMedia(exercise: exercise, height: 240),
          if (exercise.images.isEmpty && myPhotos.isEmpty)
            TextButton.icon(
              onPressed: () async {
                final picked = await FilePicker.pickFiles(type: FileType.image);
                final path = picked.firstOrNull?.path;
                if (path != null) {
                  await ref
                      .read(customImagesProvider.notifier)
                      .add(exercise.id, path);
                }
              },
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(tr('Add a photo')),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _tag(exercise.equipmentLabel),
              _tag(
                exercise.level[0].toUpperCase() + exercise.level.substring(1),
              ),
              if (exercise.custom) _tag(tr('My exercise')),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            tr('Muscles worked'),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          BodyDiagram(
            primary: exercise.primaryMuscles.toSet(),
            secondary: exercise.secondaryMuscles.toSet(),
          ),
          if (pb != null || history.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              tr('Your progress'),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            if (pb != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.emoji_events_outlined),
                title: Text(tr('Best: {label}', {'label': pb.label})),
                subtitle: Text(DateFormat('d MMM y').format(pb.date)),
              ),
            for (final h in history.take(6))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${DateFormat('d MMM').format(h.date)}   '
                  '${[for (final s in h.sets) s.seconds > 0
                        ? '${s.seconds}s'
                        : s.weightKg > 0
                        ? '${fmtKg(s.weightKg)}×${s.reps}'
                        : '${s.reps}'].join('  ')}',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
          ],
          if (exercise.instructions.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              tr('How to do it'),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            for (final (i, step) in exercise.instructions.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 11,
                      backgroundColor: fitnessAccent.withValues(alpha: 0.2),
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(step, style: const TextStyle(height: 1.4)),
                    ),
                  ],
                ),
              ),
          ],
          if (!exercise.custom)
            Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                tr('From free-exercise-db (public domain).'),
                style: TextStyle(fontSize: 11, color: Colors.white38),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tag(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white10,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(text, style: const TextStyle(fontSize: 12)),
  );

  Future<void> _addToRoutine(BuildContext context, WidgetRef ref) async {
    final routines = ref.read(routinesProvider);
    final r = await showModalBottomSheet<Routine>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(
                tr('Add to which workout?'),
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            for (final r in routines)
              ListTile(
                leading: const Icon(Icons.event_note),
                title: Text(r.name),
                onTap: () => Navigator.pop(context, r),
              ),
          ],
        ),
      ),
    );
    if (r == null) return;
    await ref
        .read(routinesProvider.notifier)
        .update(
          r.copyWith(
            items: [
              ...r.items,
              PlanItem(exerciseId: exerciseId),
            ],
          ),
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Added to {name}', {'name': r.name}))),
      );
    }
  }
}
