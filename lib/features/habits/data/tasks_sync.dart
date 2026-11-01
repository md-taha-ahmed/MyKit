import '../domain/habit_models.dart';
import 'google_tasks_api.dart';

/// Everything the to-do keeps for syncing with Google Tasks.
class TasksData {
  const TasksData({
    required this.lists,
    required this.tasks,
    this.goneTasks = const [],
    this.goneLists = const [],
    this.syncedAt = const {},
  });

  final List<TaskList> lists;
  final List<HabitTask> tasks;

  /// Deleted here, still to delete in Google.
  final List<({String gid, String list})> goneTasks;
  final List<String> goneLists;

  /// When each Google list was last pulled; later pulls fetch only changes.
  final Map<String, DateTime> syncedAt;
}

/// Two-way sync of the to-do with Google Tasks. Offline-first: everything
/// works locally, and a sync (when there's internet) pushes local changes and
/// pulls Google's. On a conflict the newer edit wins.
///
/// Progress is kept as it goes: if the connection drops halfway, what was
/// synced stays synced (no duplicates next time) and [error] says why.
class TasksSync {
  TasksSync(this._api);

  final GoogleTasksApi _api;

  Future<({TasksData data, Object? error})> run(TasksData d) async {
    final lists = [...d.lists];
    final tasks = [...d.tasks];
    final goneTasks = [...d.goneTasks];
    final goneLists = [...d.goneLists];
    final syncedAt = {...d.syncedAt};
    Object? error;

    try {
      // Lists (categories) ---------------------------------------------------
      final remote = await _api.lists();
      final remoteIds = {for (final l in remote) l.id};
      for (final gid in [...goneLists]) {
        if (remoteIds.remove(gid)) await _api.deleteList(gid);
        goneLists.remove(gid);
      }
      for (var i = 0; i < lists.length; i++) {
        final l = lists[i];
        if (l.gid == null) {
          if (l.id == TaskList.defaultId) {
            // Your local list becomes your default Google list.
            final gid = await _api.defaultListId();
            lists[i] = l.synced(
              gid,
              title: remote.where((r) => r.id == gid).firstOrNull?.title,
            );
          } else {
            // A list of the same name there (after reconnecting) is this one.
            final same = remote
                .where(
                  (r) => r.title == l.title && !lists.any((x) => x.gid == r.id),
                )
                .firstOrNull;
            lists[i] = l.synced(same?.id ?? await _api.createList(l.title));
          }
          remoteIds.add(lists[i].gid!);
        } else if (l.dirty && remoteIds.contains(l.gid)) {
          await _api.renameList(l.gid!, l.title);
          lists[i] = l.synced(l.gid!);
        }
      }
      for (final r in remote) {
        if (!remoteIds.contains(r.id)) continue;
        final i = lists.indexWhere((l) => l.gid == r.id);
        if (i < 0) {
          lists.add(
            TaskList(id: r.id, title: r.title, gid: r.id, dirty: false),
          );
        } else if (!lists[i].dirty && lists[i].title != r.title) {
          lists[i] = lists[i].synced(r.id, title: r.title);
        }
      }
      // Lists deleted in Google go here too, with their tasks.
      final dropped = {
        for (final l in lists)
          if (l.gid != null && !remoteIds.contains(l.gid)) l.id,
      };
      lists.removeWhere((l) => dropped.contains(l.id));
      tasks.removeWhere((t) => dropped.contains(t.listId));

      // Pull ------------------------------------------------------------------
      for (final l in [...lists]) {
        final gid = l.gid!;
        // A little overlap, so nothing slips between two syncs.
        final started = DateTime.now().subtract(const Duration(minutes: 2));
        final gone = {for (final g in goneTasks) g.gid};
        for (final r in await _api.tasks(gid, since: syncedAt[gid])) {
          var i = tasks.indexWhere((t) => t.gid == r.id);
          // Not synced yet, but the same task (after reconnecting).
          if (i < 0) {
            i = tasks.indexWhere(
              (t) => t.gid == null && t.listId == l.id && t.title == r.title,
            );
          }
          if (r.deleted) {
            if (i >= 0) tasks.removeAt(i);
            continue;
          }
          if (gone.contains(r.id)) continue;
          final doneAt = r.done ? (r.completed ?? r.updated) : null;
          if (i < 0) {
            tasks.add(
              HabitTask(
                id: 'g-${r.id}',
                title: r.title,
                note: r.notes,
                due: r.due,
                doneAt: doneAt,
                createdAt: r.updated,
                listId: l.id,
                gid: r.id,
                gList: gid,
                updatedAt: r.updated,
                dirty: false,
              ),
            );
            continue;
          }
          final local = tasks[i];
          if (local.dirty && local.changed.isAfter(r.updated)) {
            // Ours is newer: pushed below, onto the same Google task.
            if (local.gid == null) tasks[i] = local.linked(r.id, gid);
            continue;
          }
          tasks[i] = local.synced(
            gid: r.id,
            gList: gid,
            listId: l.id,
            title: r.title,
            note: r.notes,
            due: r.due,
            doneAt: local.done && doneAt != null ? local.doneAt : doneAt,
            updatedAt: r.updated,
            fromRemote: true,
          );
        }
        syncedAt[gid] = started;
      }

      // Push ------------------------------------------------------------------
      for (final g in [...goneTasks]) {
        await _api.delete(g.list, g.gid);
        goneTasks.remove(g);
      }
      for (var i = 0; i < tasks.length; i++) {
        final t = tasks[i];
        if (!t.dirty) continue;
        final list = lists.where((l) => l.id == t.listId).firstOrNull?.gid;
        if (list == null) continue;
        final body = GoogleTasksApi.body(
          title: t.title,
          notes: t.note,
          due: t.due,
          doneAt: t.doneAt,
        );
        RemoteTask? r;
        if (t.gid != null && t.gList == list) {
          r = await _api.patch(list, t.gid!, body);
        } else if (t.gid != null) {
          // Moved to another category.
          await _api.delete(t.gList!, t.gid!);
        }
        r ??= await _api.insert(list, body);
        tasks[i] = t.synced(gid: r.id, gList: list, updatedAt: r.updated);
      }
    } catch (e) {
      error = e;
    }

    return (
      data: TasksData(
        lists: lists,
        tasks: tasks,
        goneTasks: goneTasks,
        goneLists: goneLists,
        syncedAt: syncedAt,
      ),
      error: error,
    );
  }
}
