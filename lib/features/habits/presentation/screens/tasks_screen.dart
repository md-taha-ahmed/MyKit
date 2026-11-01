import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n.dart';
import '../../domain/habit_models.dart';
import '../providers/habit_providers.dart';
import '../widgets/habit_widgets.dart';

/// A category's name; the untouched default one is translated.
String taskListName(TaskList l) =>
    l.id == TaskList.defaultId && l.gid == null ? tr(l.title) : l.title;

/// Your to-do list, in categories, synced with Google Tasks when connected.
/// The System sees it, asks about overdue ones and can add tasks itself
/// (marked ⚡).
class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  /// The category shown, or all of them.
  String? _list;

  HabitsNotifier get _notifier => ref.read(habitsProvider.notifier);

  @override
  void initState() {
    super.initState();
    Future.microtask(_notifier.syncTasks);
  }

  void _say(String? message) {
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _connect() async {
    if (!_notifier.tasksConfigured) {
      _say(
        tr(
          'Set up Google sign-in first (Backup or YouTube import), then connect.',
        ),
      );
      return;
    }
    final error = await _notifier.connectTasks();
    _say(error ?? tr('Connected to Google Tasks.'));
  }

  Future<void> _menu(String action) async {
    final s = ref.read(habitsProvider);
    final list = s.taskLists.where((l) => l.id == _list).firstOrNull;
    switch (action) {
      case 'connect':
        await _connect();
      case 'sync':
        _say(await _notifier.syncTasks() ?? tr('Synced.'));
      case 'disconnect':
        await _notifier.disconnectTasks();
        _say(tr('Stopped syncing. Your tasks stay here.'));
      case 'new':
        final name = await _askName(context, tr('New category'));
        if (name != null) {
          final id = await _notifier.addTaskList(name);
          setState(() => _list = id);
        }
      case 'rename' when list != null:
        final name = await _askName(
          context,
          tr('Rename category'),
          initial: taskListName(list),
        );
        if (name != null) await _notifier.renameTaskList(list.id, name);
      case 'delete' when list != null:
        final open = s.tasks.where((t) => t.listId == list.id).length;
        final ok = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: Text(tr('Delete "{name}"?', {'name': taskListName(list)})),
            content: Text(
              tr('Its {n} tasks are deleted too, here and in Google Tasks.', {
                'n': open,
              }),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: Text(tr('Cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(d, true),
                child: Text(tr('Delete')),
              ),
            ],
          ),
        );
        if (ok == true) {
          await _notifier.deleteTaskList(list.id);
          setState(() => _list = null);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(habitsProvider);
    final sync = ref.watch(tasksSyncProvider);
    final connected = _notifier.tasksConnected;
    if (_list != null && !s.taskLists.any((l) => l.id == _list)) _list = null;
    final current = s.taskLists.where((l) => l.id == _list).firstOrNull;
    bool shown(HabitTask t) => _list == null || t.listId == _list;

    final now = DateTime.now();
    final today = habitDay(now);
    final open = s.openTasks.where(shown).toList();
    final overdue = open.where((t) => t.overdue(now)).toList();
    final todays = open.where((t) => t.due == today).toList();
    final later = open
        .where((t) => t.due != null && t.due!.compareTo(today) > 0)
        .toList();
    final someday = open.where((t) => t.due == null).toList();
    final done = s.tasks.where((t) => t.done && shown(t)).toList()
      ..sort((a, b) => b.doneAt!.compareTo(a.doneAt!));
    final names = {for (final l in s.taskLists) l.id: taskListName(l)};
    // In "All", each task says which category it's in.
    final tag = _list == null && s.taskLists.length > 1 ? names : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('To-do')),
        actions: [
          if (connected)
            sync.busy
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    tooltip: tr('Sync now'),
                    icon: Icon(
                      sync.error == null
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_off_outlined,
                    ),
                    onPressed: () => _menu('sync'),
                  ),
          PopupMenuButton<String>(
            onSelected: _menu,
            itemBuilder: (_) => [
              PopupMenuItem(value: 'new', child: Text(tr('New category'))),
              if (current != null) ...[
                PopupMenuItem(
                  value: 'rename',
                  child: Text(tr('Rename category')),
                ),
                if (current.id != TaskList.defaultId)
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(tr('Delete category')),
                  ),
              ],
              const PopupMenuDivider(),
              if (connected) ...[
                PopupMenuItem(value: 'sync', child: Text(tr('Sync now'))),
                PopupMenuItem(
                  value: 'disconnect',
                  child: Text(tr('Stop syncing with Google Tasks')),
                ),
              ] else
                PopupMenuItem(
                  value: 'connect',
                  child: Text(tr('Sync with Google Tasks')),
                ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => editTask(context, ref, listId: _list),
        icon: const Icon(Icons.add),
        label: Text(tr('Task')),
      ),
      body: Column(
        children: [
          // Categories: one scrolling row.
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                _ListChip(
                  label: tr('All'),
                  count: s.openTasks.length,
                  selected: _list == null,
                  onTap: () => setState(() => _list = null),
                ),
                for (final l in s.taskLists)
                  _ListChip(
                    label: names[l.id]!,
                    count: s.openTasks.where((t) => t.listId == l.id).length,
                    selected: _list == l.id,
                    onTap: () => setState(() => _list = l.id),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: Text(tr('Category')),
                  onPressed: () => _menu('new'),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _say(await _notifier.syncTasks()),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                children: [
                  if (!connected)
                    Card(
                      margin: const EdgeInsets.only(top: 6, bottom: 4),
                      child: ListTile(
                        leading: const Icon(Icons.sync),
                        title: Text(tr('Sync with Google Tasks')),
                        subtitle: Text(
                          tr(
                            'See and edit the same tasks and lists in Google Tasks, Gmail and Calendar. Works offline; syncs when there is internet.',
                          ),
                        ),
                        trailing: TextButton(
                          onPressed: _connect,
                          child: Text(tr('Connect')),
                        ),
                      ),
                    )
                  else if (sync.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        sync.error!,
                        style: const TextStyle(
                          color: Colors.orangeAccent,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  if (open.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        tr(
                          'Nothing to do. Add tasks here — the System sees them and can add some for you too.',
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white60,
                          height: 1.5,
                        ),
                      ),
                    ),
                  _section(tr('OVERDUE'), overdue, Colors.orangeAccent, tag),
                  _section(tr('TODAY'), todays, habitsAccent, tag),
                  _section(tr('LATER'), later, Colors.white70, tag),
                  _section(tr('SOMEDAY'), someday, Colors.white70, tag),
                  if (done.isNotEmpty)
                    ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                      title: Text(tr('Done ({n})', {'n': done.length})),
                      children: [
                        for (final t in done.take(30))
                          _TaskTile(task: t, listName: tag?[t.listId]),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(
    String title,
    List<HabitTask> tasks,
    Color color,
    Map<String, String>? tag,
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
        for (final t in tasks) _TaskTile(task: t, listName: tag?[t.listId]),
      ],
    );
  }
}

class _ListChip extends StatelessWidget {
  const _ListChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(end: 6),
    child: ChoiceChip(
      label: Text(count > 0 ? '$label · $count' : label),
      selected: selected,
      onSelected: (_) => onTap(),
    ),
  );
}

Future<String?> _askName(
  BuildContext context,
  String title, {
  String? initial,
}) async {
  final c = TextEditingController(text: initial);
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: InputDecoration(labelText: tr('Name')),
        onSubmitted: (_) => Navigator.pop(d, true),
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
  final name = c.text.trim();
  return ok == true && name.isNotEmpty ? name : null;
}

class _TaskTile extends ConsumerWidget {
  const _TaskTile({required this.task, this.listName});

  final HabitTask task;

  /// Shown when listing every category.
  final String? listName;

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
        subtitle: switch ([
          ?listName,
          ?task.due,
          if (task.note.isNotEmpty) task.note,
        ]) {
          final parts when parts.isEmpty => null,
          final parts => Text(
            parts.join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        },
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
  String? listId,
}) async {
  final title = TextEditingController(text: task?.title);
  final note = TextEditingController(text: task?.note);
  String? due = task?.due ?? habitDay(DateTime.now());
  final lists = ref.read(habitsProvider).taskLists;
  var list = task?.listId ?? listId ?? TaskList.defaultId;
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
            if (lists.length > 1) ...[
              const SizedBox(height: 4),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final l in lists)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 6),
                        child: ChoiceChip(
                          avatar: const Icon(Icons.folder_outlined, size: 16),
                          label: Text(taskListName(l)),
                          selected: list == l.id,
                          onSelected: (_) => set(() => list = l.id),
                        ),
                      ),
                  ],
                ),
              ),
            ],
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
    await notifier.addTask(
      title.text,
      due: due,
      note: note.text.trim(),
      listId: list,
    );
  } else {
    await notifier.updateTask(
      task.copyWith(
        title: title.text.trim(),
        note: note.text.trim(),
        due: due,
        clearDue: due == null,
        listId: list,
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
