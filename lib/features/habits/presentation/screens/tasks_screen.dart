import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n.dart';
import '../../domain/habit_models.dart';
import '../providers/habit_providers.dart';
import '../widgets/habit_widgets.dart';

/// Your to-do list. The System sees it, asks about overdue ones and can add
/// tasks itself (marked ⚡).
class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(habitsProvider);
    final now = DateTime.now();
    final today = habitDay(now);
    final open = s.openTasks;
    final overdue = open.where((t) => t.overdue(now)).toList();
    final todays = open.where((t) => t.due == today).toList();
    final later = open
        .where((t) => t.due != null && t.due!.compareTo(today) > 0)
        .toList();
    final someday = open.where((t) => t.due == null).toList();
    final done = s.tasks.where((t) => t.done).toList()
      ..sort((a, b) => b.doneAt!.compareTo(a.doneAt!));

    return Scaffold(
      appBar: AppBar(title: Text(tr('To-do'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => editTask(context, ref),
        icon: const Icon(Icons.add),
        label: Text(tr('Task')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
        children: [
          if (open.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                tr(
                  'Nothing to do. Add tasks here — the System sees them and can add some for you too.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, height: 1.5),
              ),
            ),
          _section(context, ref, tr('OVERDUE'), overdue, Colors.orangeAccent),
          _section(context, ref, tr('TODAY'), todays, habitsAccent),
          _section(context, ref, tr('LATER'), later, Colors.white70),
          _section(context, ref, tr('SOMEDAY'), someday, Colors.white70),
          if (done.isNotEmpty)
            ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 4),
              title: Text(tr('Done ({n})', {'n': done.length})),
              children: [for (final t in done.take(30)) _TaskTile(task: t)],
            ),
        ],
      ),
    );
  }

  Widget _section(
    BuildContext context,
    WidgetRef ref,
    String title,
    List<HabitTask> tasks,
    Color color,
  ) {
    if (tasks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
          child: Text(
            title,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              fontSize: 12.5,
            ),
          ),
        ),
        for (final t in tasks) _TaskTile(task: t),
      ],
    );
  }
}

class _TaskTile extends ConsumerWidget {
  const _TaskTile({required this.task});

  final HabitTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(habitsProvider.notifier);
    return Dismissible(
      key: ValueKey(task.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: Colors.red.withValues(alpha: 0.3),
        child: const Icon(Icons.delete_outline),
      ),
      onDismissed: (_) => notifier.deleteTask(task.id),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: Checkbox(
          value: task.done,
          onChanged: (_) => notifier.toggleTask(task.id),
        ),
        title: Text(
          '${task.fromSystem ? '⚡ ' : ''}${task.title}',
          style: TextStyle(
            decoration: task.done ? TextDecoration.lineThrough : null,
            color: task.done ? Colors.white38 : null,
          ),
        ),
        subtitle:
            [
              if (task.due != null) task.due!,
              if (task.note.isNotEmpty) task.note,
            ].isEmpty
            ? null
            : Text(
                [
                  if (task.due != null) task.due!,
                  if (task.note.isNotEmpty) task.note,
                ].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
        onTap: () => editTask(context, ref, task: task),
      ),
    );
  }
}

/// Add or edit a task: title, note, due date.
Future<void> editTask(
  BuildContext context,
  WidgetRef ref, {
  HabitTask? task,
}) async {
  final title = TextEditingController(text: task?.title);
  final note = TextEditingController(text: task?.note);
  String? due = task?.due ?? habitDay(DateTime.now());
  final ok = await showModalBottomSheet<bool>(
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: title,
              autofocus: task == null,
              decoration: InputDecoration(labelText: tr('Task')),
            ),
            TextField(
              controller: note,
              decoration: InputDecoration(labelText: tr('Note (optional)')),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: [
                ChoiceChip(
                  label: Text(tr('Today')),
                  selected: due == habitDay(DateTime.now()),
                  onSelected: (_) => set(() => due = habitDay(DateTime.now())),
                ),
                ChoiceChip(
                  label: Text(tr('Tomorrow')),
                  selected:
                      due ==
                      habitDay(DateTime.now().add(const Duration(days: 1))),
                  onSelected: (_) => set(
                    () => due = habitDay(
                      DateTime.now().add(const Duration(days: 1)),
                    ),
                  ),
                ),
                ChoiceChip(
                  label: Text(tr('Someday')),
                  selected: due == null,
                  onSelected: (_) => set(() => due = null),
                ),
                ActionChip(
                  avatar: const Icon(Icons.event, size: 16),
                  label: Text(due ?? tr('Pick a date')),
                  onPressed: () async {
                    final now = DateTime.now();
                    final d = await showDatePicker(
                      context: sheet,
                      firstDate: now.subtract(const Duration(days: 365)),
                      lastDate: now.add(const Duration(days: 365 * 3)),
                      initialDate: due == null ? now : parseHabitDay(due!),
                    );
                    if (d != null) set(() => due = habitDay(d));
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (task != null)
                  TextButton(
                    onPressed: () async {
                      await ref
                          .read(habitsProvider.notifier)
                          .deleteTask(task.id);
                      if (sheet.mounted) Navigator.pop(sheet, false);
                    },
                    child: Text(tr('Delete')),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.pop(sheet, true),
                  child: Text(tr('Save')),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  if (ok != true || title.text.trim().isEmpty) return;
  final notifier = ref.read(habitsProvider.notifier);
  if (task == null) {
    await notifier.addTask(title.text, due: due, note: note.text.trim());
  } else {
    await notifier.updateTask(
      task.copyWith(
        title: title.text.trim(),
        note: note.text.trim(),
        due: due,
        clearDue: due == null,
      ),
    );
  }
}

/// A compact "tasks" panel for the System's home.
class TasksPanel extends ConsumerWidget {
  const TasksPanel({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(habitsProvider);
    final now = DateTime.now();
    final today = habitDay(now);
    final relevant = s.openTasks
        .where((t) => t.overdue(now) || t.due == today)
        .toList();
    return SystemPanel(
      title: tr('[SYSTEM] TO-DO'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (relevant.isEmpty)
            Text(
              s.openTasks.isEmpty
                  ? tr('No tasks.')
                  : tr('{n} open, none due today.', {'n': s.openTasks.length}),
              style: const TextStyle(color: Colors.white60),
            ),
          for (final t in relevant.take(5)) _TaskTile(task: t),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => editTask(context, ref),
                icon: const Icon(Icons.add, size: 18),
                label: Text(tr('Task')),
              ),
              const Spacer(),
              TextButton(onPressed: onOpen, child: Text(tr('All tasks'))),
            ],
          ),
        ],
      ),
    );
  }
}
