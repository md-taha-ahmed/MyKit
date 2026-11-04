import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/i18n.dart';
import '../../domain/entities/fitness_entities.dart';
import '../../fitness_routes.dart';
import '../providers/fitness_providers.dart';
import '../widgets/exercise_media.dart';
import '../widgets/fitness_sheets.dart';

/// Searchable exercise library. [picker]: tapping returns the exercise id;
/// [embedded]: shown as a tab of the home screen.
class ExerciseListScreen extends ConsumerStatefulWidget {
  const ExerciseListScreen({
    super.key,
    this.picker = false,
    this.embedded = false,
  });

  final bool picker;
  final bool embedded;

  @override
  ConsumerState<ExerciseListScreen> createState() => _ExerciseListScreenState();
}

class _ExerciseListScreenState extends ConsumerState<ExerciseListScreen> {
  String _query = '';
  bool _homeOnly = true;
  String? _muscle;

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(exerciseLibraryProvider);
    final q = _query.toLowerCase();

    final body = library.when(
      loading: () => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text(tr('Downloading the exercise library…')),
          ],
        ),
      ),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$e', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => ref.invalidate(exerciseLibraryProvider),
                child: Text(tr('Retry')),
              ),
            ],
          ),
        ),
      ),
      data: (all) {
        final list =
            all.values
                .where(
                  (e) =>
                      (!_homeOnly || e.isHome) &&
                      (_muscle == null ||
                          e.primaryMuscles.contains(_muscle) ||
                          e.secondaryMuscles.contains(_muscle)) &&
                      (q.isEmpty || e.name.toLowerCase().contains(q)),
                )
                .toList()
              ..sort((a, b) {
                // Own exercises first, then primary-muscle matches.
                if (a.custom != b.custom) return a.custom ? -1 : 1;
                if (_muscle != null) {
                  final pa = a.primaryMuscles.contains(_muscle);
                  final pb = b.primaryMuscles.contains(_muscle);
                  if (pa != pb) return pa ? -1 : 1;
                }
                return a.name.compareTo(b.name);
              });
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 96),
          itemCount: list.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Text(
                  plural(list.length, 'exercise'),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              );
            }
            final e = list[i - 1];
            return ListTile(
              leading: ExerciseThumb(exercise: e),
              title: Text(e.name),
              subtitle: Text(
                [
                  e.equipmentLabel,
                  e.primaryMuscles.map(Muscle.label).join(', '),
                  if (e.custom) tr('Mine'),
                ].where((s) => s.isNotEmpty).join(' · '),
                style: const TextStyle(color: Colors.white60),
              ),
              trailing: widget.picker
                  ? IconButton(
                      tooltip: tr('Details'),
                      icon: const Icon(Icons.info_outline),
                      onPressed: () =>
                          context.push(FitnessRoutes.exercise(e.id)),
                    )
                  : null,
              onTap: () => widget.picker
                  ? context.pop(e.id)
                  : context.push(FitnessRoutes.exercise(e.id)),
            );
          },
        );
      },
    );

    final filters = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            decoration: InputDecoration(
              hintText: tr('Search exercises'),
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(tr('Home equipment')),
                  selected: _homeOnly,
                  selectedColor: fitnessAccent.withValues(alpha: 0.3),
                  onSelected: (v) => setState(() => _homeOnly = v),
                ),
              ),
              for (final m in Muscle.all)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(Muscle.label(m)),
                    selected: _muscle == m,
                    selectedColor: fitnessAccent.withValues(alpha: 0.3),
                    onSelected: (v) => setState(() => _muscle = v ? m : null),
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    final content = Column(
      children: [
        filters,
        Expanded(child: body),
      ],
    );

    final addButton = FloatingActionButton.extended(
      shape: const StadiumBorder(),
      backgroundColor: fitnessAccent,
      foregroundColor: Colors.black,
      onPressed: () async {
        final created = await showAddExerciseSheet(context, ref);
        if (created != null && context.mounted && widget.picker) {
          context.pop(created.id);
        }
      },
      icon: const Icon(Icons.add),
      label: Text(tr('My exercise')),
    );

    if (widget.embedded) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('Exercises'))),
        body: content,
        floatingActionButton: addButton,
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.picker ? tr('Add exercise') : tr('Exercises')),
      ),
      body: content,
      floatingActionButton: addButton,
    );
  }
}

/// Create an exercise that isn't in the database (photos can be added on
/// its page).
Future<Exercise?> showAddExerciseSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  final name = TextEditingController();
  final steps = TextEditingController();
  String? equipment = 'body only';
  final primary = <String>{};
  final secondary = <String>{};

  final result = await showModalBottomSheet<Exercise>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr('New exercise'),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: name,
                autofocus: true,
                decoration: InputDecoration(labelText: tr('Name')),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String?>(
                segments: [
                  ButtonSegment(
                    value: 'body only',
                    label: Text(tr('Bodyweight')),
                  ),
                  ButtonSegment(value: 'dumbbell', label: Text(tr('Dumbbell'))),
                  ButtonSegment(value: 'other', label: Text(tr('Other'))),
                ],
                selected: {equipment},
                onSelectionChanged: (v) => setSheet(() => equipment = v.first),
              ),
              const SizedBox(height: 14),
              Text(tr('Main muscles')),
              Wrap(
                spacing: 6,
                children: [
                  for (final m in Muscle.all)
                    FilterChip(
                      label: Text(Muscle.label(m)),
                      selected: primary.contains(m),
                      selectedColor: fitnessAccent.withValues(alpha: 0.35),
                      onSelected: (v) => setSheet(() {
                        v ? primary.add(m) : primary.remove(m);
                        secondary.remove(m);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(tr('Also works (optional)')),
              Wrap(
                spacing: 6,
                children: [
                  for (final m in Muscle.all)
                    if (!primary.contains(m))
                      FilterChip(
                        label: Text(Muscle.label(m)),
                        selected: secondary.contains(m),
                        selectedColor: fitnessAccent.withValues(alpha: 0.18),
                        onSelected: (v) => setSheet(
                          () => v ? secondary.add(m) : secondary.remove(m),
                        ),
                      ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: steps,
                minLines: 2,
                maxLines: 6,
                decoration: InputDecoration(
                  labelText: tr('How to do it (one step per line, optional)'),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: fitnessAccent,
                  foregroundColor: Colors.black,
                ),
                onPressed: () async {
                  if (name.text.trim().isEmpty || primary.isEmpty) return;
                  final e = await ref
                      .read(customExercisesProvider.notifier)
                      .add(
                        name: name.text,
                        equipment: equipment,
                        primary: primary.toList(),
                        secondary: secondary.toList(),
                        instructions: steps.text
                            .split('\n')
                            .map((s) => s.trim())
                            .where((s) => s.isNotEmpty)
                            .toList(),
                      );
                  if (context.mounted) Navigator.pop(context, e);
                },
                child: Text(tr('Create')),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  name.dispose();
  steps.dispose();
  return result;
}
