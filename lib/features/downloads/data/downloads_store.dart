import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../domain/download_item.dart';

/// The list of downloads, kept as `index.json` next to the files. (Not in
/// shared preferences: those go into the Drive backup, and the files don't.)
class DownloadsStore {
  DownloadsStore(this.root);

  final Directory root;

  File get _index => File('${root.path}/index.json');

  List<DownloadItem> load() {
    try {
      if (!_index.existsSync()) return [];
      final raw = jsonDecode(_index.readAsStringSync()) as List;
      return [
        for (final j in raw.cast<Map<String, dynamic>>())
          DownloadItem.fromJson(j),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _pending = Future.value();

  /// Saves in order; each write replaces the file whole.
  Future<void> save(List<DownloadItem> items) {
    final json = jsonEncode([for (final i in items) i.toJson()]);
    return _pending = _pending.then((_) async {
      try {
        await root.create(recursive: true);
        final tmp = File('${_index.path}.tmp');
        await tmp.writeAsString(json, flush: true);
        await tmp.rename(_index.path);
      } catch (_) {
        // Disk full or similar; the next save tries again.
      }
    });
  }

  Directory folderFor(String id) => Directory('${root.path}/$id');

  Directory get covers => Directory('${root.path}/covers');
}

/// The "Downloading…" notification that keeps the app alive, and free space.
class DownloadsNative {
  static const _channel = MethodChannel('com.mdtaha.mykit/downloads');

  Future<void> keepAlive(String title, String text, int progress) async {
    try {
      await _channel.invokeMethod<void>('keepAlive', {
        'title': title,
        'text': text,
        'progress': progress,
      });
    } catch (_) {}
  }

  Future<void> release() async {
    try {
      await _channel.invokeMethod<void>('release');
    } catch (_) {}
  }

  Future<int?> freeSpace(String path) async {
    try {
      return await _channel.invokeMethod<int>('freeSpace', {'path': path});
    } catch (_) {
      return null;
    }
  }
}

/// Total size of the files in [dir].
Future<int> folderSize(Directory dir) async {
  var total = 0;
  if (!await dir.exists()) return 0;
  await for (final f in dir.list(recursive: true, followLinks: false)) {
    if (f is File) total += await f.length();
  }
  return total;
}
