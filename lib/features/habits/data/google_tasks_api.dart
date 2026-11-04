import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/google/google_oauth.dart';
import '../../../core/i18n/i18n.dart';

class TasksSyncException implements Exception {
  const TasksSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A task as Google Tasks has it.
typedef RemoteTask = ({
  String id,
  String title,
  String notes,
  bool done,
  DateTime? completed,
  String? due,
  DateTime updated,
  bool deleted,
});

/// Google Tasks API v1, signed in through [GoogleOAuth] (scope `tasks`).
/// Requests ask only for the fields MyKit uses, to keep data small.
class GoogleTasksApi {
  GoogleTasksApi(this._oauth, this._client);

  final GoogleOAuth _oauth;
  final http.Client _client;

  static const scopes = ['https://www.googleapis.com/auth/tasks'];
  static const _host = 'tasks.googleapis.com';
  static const _taskFields =
      'id,title,notes,status,completed,due,updated,deleted';

  bool get isConfigured => _oauth.isConfigured;
  bool get isConnected => _oauth.hasGranted(scopes);

  /// Signs in (browser) if needed.
  Future<void> connect() => _token(interactive: true);

  Future<List<({String id, String title})>> lists() async {
    final out = <({String id, String title})>[];
    String? page;
    do {
      final body = await _json('GET', '/tasks/v1/users/@me/lists', {
        'maxResults': '100',
        'fields': 'items(id,title),nextPageToken',
        'pageToken': ?page,
      });
      for (final l in (body['items'] as List? ?? const [])) {
        out.add((id: l['id'] as String, title: l['title'] as String? ?? ''));
      }
      page = body['nextPageToken'] as String?;
    } while (page != null);
    return out;
  }

  Future<String> defaultListId() async =>
      (await _json('GET', '/tasks/v1/users/@me/lists/@default', {
            'fields': 'id',
          }))['id']
          as String;

  Future<String> createList(String title) async =>
      (await _json(
            'POST',
            '/tasks/v1/users/@me/lists',
            {'fields': 'id'},
            {'title': title},
          ))['id']
          as String;

  Future<void> renameList(String id, String title) => _json(
    'PATCH',
    '/tasks/v1/users/@me/lists/$id',
    {'fields': 'id'},
    {'title': title},
  );

  Future<void> deleteList(String id) =>
      _json('DELETE', '/tasks/v1/users/@me/lists/$id');

  /// Tasks of [list], done ones too. With [since], only what changed after
  /// it — deletions included.
  Future<List<RemoteTask>> tasks(String list, {DateTime? since}) async {
    final out = <RemoteTask>[];
    final oldDone = DateTime.now().subtract(const Duration(days: 30));
    String? page;
    do {
      final body = await _json('GET', '/tasks/v1/lists/$list/tasks', {
        'maxResults': '100',
        'showCompleted': 'true',
        'showHidden': 'true',
        'fields': 'items($_taskFields),nextPageToken',
        // Later syncs: only what changed, deletions included. (No
        // completedMin on the first one: Google would drop open tasks.)
        if (since != null) ...{
          'showDeleted': 'true',
          'updatedMin': since.toUtc().toIso8601String(),
        },
        'pageToken': ?page,
      });
      for (final t in (body['items'] as List? ?? const [])) {
        final task = _task(t as Map<String, dynamic>);
        // First sync: open tasks and the last month of done ones.
        if (since == null && task.done && task.updated.isBefore(oldDone)) {
          continue;
        }
        out.add(task);
      }
      page = body['nextPageToken'] as String?;
    } while (page != null);
    return out;
  }

  Future<RemoteTask> insert(String list, Map<String, dynamic> task) async =>
      _task(
        await _json('POST', '/tasks/v1/lists/$list/tasks', {
          'fields': _taskFields,
        }, task),
      );

  /// Null when the task is gone from Google (deleted there).
  Future<RemoteTask?> patch(
    String list,
    String id,
    Map<String, dynamic> task,
  ) async {
    final j = await _json(
      'PATCH',
      '/tasks/v1/lists/$list/tasks/$id',
      {'fields': _taskFields},
      task,
      {404},
    );
    return j.isEmpty ? null : _task(j);
  }

  /// Deleting something already gone is fine.
  Future<void> delete(String list, String id) =>
      _json('DELETE', '/tasks/v1/lists/$list/tasks/$id', null, null, {404});

  /// The body Google expects for a task. Due dates are dates only (Google
  /// ignores the time).
  static Map<String, dynamic> body({
    required String title,
    required String notes,
    required String? due,
    required DateTime? doneAt,
  }) => {
    'title': title,
    'notes': notes,
    'due': due == null ? null : '${due}T00:00:00.000Z',
    'status': doneAt == null ? 'needsAction' : 'completed',
    'completed': doneAt?.toUtc().toIso8601String(),
  };

  static RemoteTask _task(Map<String, dynamic> t) => (
    id: t['id'] as String,
    title: t['title'] as String? ?? '',
    notes: t['notes'] as String? ?? '',
    done: t['status'] == 'completed',
    completed: DateTime.tryParse(t['completed'] as String? ?? '')?.toLocal(),
    due: switch (t['due']) {
      final String d when d.length >= 10 => d.substring(0, 10),
      _ => null,
    },
    updated:
        DateTime.tryParse(t['updated'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
    deleted: t['deleted'] == true,
  );

  Future<String> _token({bool interactive = false}) async {
    try {
      return await _oauth.accessToken(scopes, interactive: interactive);
    } on GoogleOAuthException catch (e) {
      throw TasksSyncException(e.message);
    }
  }

  /// Sends a request; retries once with a new token on 401.
  Future<Map<String, dynamic>> _json(
    String method,
    String path, [
    Map<String, String>? query,
    Map<String, dynamic>? body,
    Set<int> okCodes = const {},
  ]) async {
    for (var attempt = 0; ; attempt++) {
      final request = http.Request(method, Uri.https(_host, path, query))
        ..headers['Authorization'] = 'Bearer ${await _token()}';
      if (body != null) {
        request
          ..headers['Content-Type'] = 'application/json; charset=UTF-8'
          ..body = jsonEncode(body);
      }
      final res = await http.Response.fromStream(await _client.send(request));
      if (res.statusCode == 401 && attempt == 0) {
        _oauth.invalidateAccessToken();
        continue;
      }
      if (okCodes.contains(res.statusCode)) return const {};
      if (res.statusCode >= 300) throw TasksSyncException(_apiError(res));
      if (res.body.isEmpty) return const {};
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
  }

  static String _apiError(http.Response res) {
    try {
      final error =
          (jsonDecode(res.body) as Map<String, dynamic>)['error'] as Map?;
      final reason =
          ((error?['errors'] as List?)?.firstOrNull as Map?)?['reason'];
      if (reason == 'accessNotConfigured' ||
          '${error?['message']}'.contains('has not been used')) {
        return tr(
          'Turn on the Google Tasks API in your Google Cloud project, then try again.',
        );
      }
      if (error?['message'] case final String message) return message;
    } catch (_) {}
    return tr('Google Tasks error ({code}).', {'code': res.statusCode});
  }
}
