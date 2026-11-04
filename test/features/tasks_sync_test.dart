import 'package:flutter_test/flutter_test.dart';
import 'package:mykit/features/habits/data/google_tasks_api.dart';
import 'package:mykit/features/habits/data/tasks_sync.dart';
import 'package:mykit/features/habits/domain/habit_models.dart';

/// Google Tasks in memory.
class _FakeGoogle implements GoogleTasksApi {
  final named = <String, String>{'g-default': 'My Tasks'};
  final tasksIn = <String, Map<String, RemoteTask>>{'g-default': {}};
  var _n = 0;
  var failAfter = -1;
  var calls = 0;

  void _call() {
    if (failAfter >= 0 && calls++ >= failAfter) {
      throw const TasksSyncException('offline');
    }
  }

  RemoteTask _make(String id, Map<String, dynamic> b) => (
    id: id,
    title: b['title'] as String,
    notes: b['notes'] as String? ?? '',
    done: b['status'] == 'completed',
    completed: null,
    due: (b['due'] as String?)?.substring(0, 10),
    updated: DateTime.now(),
    deleted: false,
  );

  @override
  bool get isConfigured => true;
  @override
  bool get isConnected => true;
  @override
  Future<void> connect() async {}

  @override
  Future<List<({String id, String title})>> lists() async {
    _call();
    return [for (final e in named.entries) (id: e.key, title: e.value)];
  }

  @override
  Future<String> defaultListId() async => 'g-default';

  @override
  Future<String> createList(String title) async {
    _call();
    final id = 'gl${_n++}';
    named[id] = title;
    tasksIn[id] = {};
    return id;
  }

  @override
  Future<void> renameList(String id, String title) async => named[id] = title;

  @override
  Future<void> deleteList(String id) async {
    named.remove(id);
    tasksIn.remove(id);
  }

  @override
  Future<List<RemoteTask>> tasks(String list, {DateTime? since}) async {
    _call();
    return [...?tasksIn[list]?.values];
  }

  @override
  Future<RemoteTask> insert(String list, Map<String, dynamic> task) async {
    _call();
    final t = _make('gt${_n++}', task);
    tasksIn[list]![t.id] = t;
    return t;
  }

  @override
  Future<RemoteTask?> patch(
    String list,
    String id,
    Map<String, dynamic> task,
  ) async {
    _call();
    if (tasksIn[list]?[id] == null) return null;
    return tasksIn[list]![id] = _make(id, task);
  }

  @override
  Future<void> delete(String list, String id) async {
    _call();
    tasksIn[list]?.remove(id);
  }
}

HabitTask _task(String id, String title, {String list = TaskList.defaultId}) =>
    HabitTask(
      id: id,
      title: title,
      createdAt: DateTime(2026, 11, 1),
      listId: list,
    );

void main() {
  const localDefault = TaskList(id: TaskList.defaultId, title: 'My Tasks');

  test(
    'first sync: local default list becomes Google\'s, tasks go up',
    () async {
      final g = _FakeGoogle();
      final r = await TasksSync(g).run(
        TasksData(
          lists: const [
            localDefault,
            TaskList(id: 'work', title: 'Work'),
          ],
          tasks: [
            _task('a', 'Buy bread'),
            _task('b', 'Send CV', list: 'work'),
          ],
        ),
      );
      expect(r.error, isNull);
      expect(g.named.length, 2, reason: 'no duplicate default list');
      expect(r.data.lists.first.gid, 'g-default');
      expect(r.data.tasks.every((t) => !t.dirty && t.gid != null), isTrue);
      expect(g.tasksIn['g-default']!.values.single.title, 'Buy bread');
      expect(g.tasksIn[r.data.lists[1].gid]!.values.single.title, 'Send CV');
    },
  );

  test('pulls Google lists and tasks as categories', () async {
    final g = _FakeGoogle()
      ..named['g-home'] = 'Home'
      ..tasksIn['g-home'] = {
        'x': (
          id: 'x',
          title: 'Fix the tap',
          notes: '',
          done: false,
          completed: null,
          due: '2026-11-03',
          updated: DateTime(2026, 11, 1),
          deleted: false,
        ),
      };
    final r = await TasksSync(
      g,
    ).run(const TasksData(lists: [localDefault], tasks: []));
    expect(r.data.lists.map((l) => l.title), containsAll(['Home']));
    final t = r.data.tasks.single;
    expect(t.title, 'Fix the tap');
    expect(t.due, '2026-11-03');
    expect(t.listId, 'g-home');
  });

  test('a dropped connection keeps what was synced (no duplicates)', () async {
    final g = _FakeGoogle()..failAfter = 3; // lists, pull, first insert
    final first = await TasksSync(g).run(
      TasksData(
        lists: const [localDefault],
        tasks: [_task('a', 'One'), _task('b', 'Two')],
      ),
    );
    expect(first.error, isA<TasksSyncException>());
    expect(first.data.tasks.where((t) => t.gid != null).length, 1);

    g.failAfter = -1;
    final second = await TasksSync(g).run(first.data);
    expect(second.error, isNull);
    expect(g.tasksIn['g-default']!.length, 2);
  });

  test('deleted and moved tasks', () async {
    final g = _FakeGoogle();
    var d = (await TasksSync(g).run(
      TasksData(
        lists: const [
          localDefault,
          TaskList(id: 'w', title: 'Work'),
        ],
        tasks: [_task('a', 'Stay'), _task('b', 'Go')],
      ),
    )).data;
    final b = d.tasks.firstWhere((t) => t.id == 'b');
    final a = d.tasks.firstWhere((t) => t.id == 'a');
    d = TasksData(
      lists: d.lists,
      tasks: [a.copyWith(listId: 'w')],
      goneTasks: [(gid: b.gid!, list: b.gList!)],
      syncedAt: d.syncedAt,
    );
    d = (await TasksSync(g).run(d)).data;
    expect(g.tasksIn['g-default'], isEmpty);
    final work = d.lists.firstWhere((l) => l.id == 'w').gid;
    expect(g.tasksIn[work]!.values.single.title, 'Stay');
    expect(d.goneTasks, isEmpty);
  });

  test(
    'reconnecting adopts the same list and task instead of copying',
    () async {
      final g = _FakeGoogle()..named['g-w'] = 'Work';
      g.tasksIn['g-w'] = {
        'x': (
          id: 'x',
          title: 'Send CV',
          notes: '',
          done: false,
          completed: null,
          due: null,
          updated: DateTime(2026, 10, 1),
          deleted: false,
        ),
      };
      final r = await TasksSync(g).run(
        TasksData(
          lists: const [
            localDefault,
            TaskList(id: 'w', title: 'Work'),
          ],
          tasks: [_task('b', 'Send CV', list: 'w')],
        ),
      );
      expect(g.named.length, 2);
      expect(g.tasksIn['g-w']!.length, 1);
      expect(r.data.tasks.single.gid, 'x');
    },
  );
}
