import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../../core/google/google_oauth.dart';
import '../../domain/entities/drive_backup.dart';

/// Backup files in the user's Google Drive **app data folder**: a hidden
/// folder only MyKit can see (scope `drive.appdata` — no access to the rest
/// of the Drive). Signs in through [GoogleOAuth] like the YouTube import.
class DriveBackupDataSource {
  DriveBackupDataSource(this._oauth, this._client);

  final GoogleOAuth _oauth;
  final http.Client _client;

  static const _scopes = ['https://www.googleapis.com/auth/drive.appdata'];
  static const _fields = 'id,name,createdTime,size';

  bool get isConfigured => _oauth.isConfigured;
  bool get isSignedIn => _oauth.hasGranted(_scopes);

  /// Signs in (browser) if needed.
  Future<void> signIn() => _token(interactive: true);

  /// Newest first.
  Future<List<DriveBackup>> list({bool interactive = false}) async {
    final res = await _send(
      () => http.Request(
        'GET',
        Uri.https('www.googleapis.com', '/drive/v3/files', {
          'spaces': 'appDataFolder',
          'fields': 'files($_fields)',
          'orderBy': 'createdTime desc',
          'pageSize': '100',
        }),
      ),
      interactive: interactive,
    );
    final files = (jsonDecode(res.body) as Map<String, dynamic>)['files'];
    return [for (final f in (files as List? ?? const [])) _backup(f as Map)];
  }

  Future<DriveBackup> upload(
    String name,
    Uint8List bytes, {
    bool interactive = false,
  }) async {
    const boundary = 'mykit-backup-boundary';
    final head = utf8.encode(
      '--$boundary\r\n'
      'Content-Type: application/json; charset=UTF-8\r\n\r\n'
      '${jsonEncode({
        'name': name,
        'parents': ['appDataFolder'],
      })}\r\n'
      '--$boundary\r\n'
      'Content-Type: application/gzip\r\n\r\n',
    );
    final tail = utf8.encode('\r\n--$boundary--\r\n');
    final body = Uint8List.fromList([...head, ...bytes, ...tail]);

    final res = await _send(
      () =>
          http.Request(
              'POST',
              Uri.https('www.googleapis.com', '/upload/drive/v3/files', {
                'uploadType': 'multipart',
                'fields': _fields,
              }),
            )
            ..headers['Content-Type'] = 'multipart/related; boundary=$boundary'
            ..bodyBytes = body,
      interactive: interactive,
    );
    return _backup(jsonDecode(res.body) as Map);
  }

  Future<Uint8List> download(String id) async {
    final res = await _send(
      () => http.Request(
        'GET',
        Uri.https('www.googleapis.com', '/drive/v3/files/$id', {
          'alt': 'media',
        }),
      ),
      interactive: true,
    );
    return res.bodyBytes;
  }

  Future<void> delete(String id) => _send(
    () => http.Request(
      'DELETE',
      Uri.https('www.googleapis.com', '/drive/v3/files/$id'),
    ),
  );

  Future<String> _token({bool interactive = false}) async {
    try {
      return await _oauth.accessToken(_scopes, interactive: interactive);
    } on GoogleOAuthException catch (e) {
      throw BackupException(e.message);
    }
  }

  /// Sends a fresh request from [build]; retries once with a new token on 401.
  Future<http.Response> _send(
    http.Request Function() build, {
    bool interactive = false,
  }) async {
    for (var attempt = 0; ; attempt++) {
      final request = build()
        ..headers['Authorization'] =
            'Bearer ${await _token(interactive: interactive)}';
      final res = await http.Response.fromStream(await _client.send(request));
      if (res.statusCode == 401 && attempt == 0) {
        _oauth.invalidateAccessToken();
        continue;
      }
      if (res.statusCode >= 300) throw BackupException(_apiError(res));
      return res;
    }
  }

  static DriveBackup _backup(Map f) => DriveBackup(
    id: f['id'] as String,
    name: f['name'] as String? ?? '',
    createdAt:
        DateTime.tryParse(f['createdTime'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
    sizeBytes: int.tryParse('${f['size'] ?? ''}') ?? 0,
  );

  static String _apiError(http.Response res) {
    try {
      final error =
          (jsonDecode(res.body) as Map<String, dynamic>)['error'] as Map?;
      final reason =
          ((error?['errors'] as List?)?.firstOrNull as Map?)?['reason'];
      if (reason == 'accessNotConfigured' ||
          '${error?['status']}' == 'PERMISSION_DENIED' &&
              '${error?['message']}'.contains('has not been used')) {
        return 'Turn on the Google Drive API in your Google Cloud project, '
            'then try again.';
      }
      if (reason == 'storageQuotaExceeded') return 'Your Google Drive is full.';
      if (error?['message'] case final String message) return message;
    } catch (_) {}
    return 'Google Drive error (${res.statusCode}).';
  }
}
