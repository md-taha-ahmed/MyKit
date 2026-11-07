/// Offline downloads shared by the Anime & Manga and Movies tools.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

enum DownloadKind { manga, anime, movie }

enum DownloadState {
  /// Waiting for its turn (or for the internet to come back, see [DownloadItem.retryAt]).
  queued,
  running,
  paused,
  failed,
  done,
}

typedef SavedTrack = ({String path, String lang});

/// One chapter, episode or movie saved (or being saved) for offline use.
///
/// [source] says what to fetch and differs by [kind]; [result] is what was
/// saved (file paths, resume points). Both are plain JSON.
class DownloadItem {
  const DownloadItem({
    required this.id,
    required this.kind,
    required this.groupKey,
    required this.groupTitle,
    required this.itemKey,
    required this.itemTitle,
    required this.dir,
    required this.addedAt,
    this.order = 0,
    this.coverUrl,
    this.coverPath,
    this.state = DownloadState.queued,
    this.progress = 0,
    this.bytes = 0,
    this.error,
    this.retryAt,
    this.source = const {},
    this.result = const {},
  });

  final String id;
  final DownloadKind kind;

  /// The title it belongs to: manga key, anime key or the movie/series id.
  final String groupKey;
  final String groupTitle;

  /// Chapter URL, episode URL or the movie/episode video id.
  final String itemKey;

  /// Chapter or episode name; empty for a movie.
  final String itemTitle;

  /// Chapter/episode number, for sorting.
  final double order;

  /// Folder holding this item's files.
  final String dir;
  final DateTime addedAt;
  final String? coverUrl;

  /// Local copy of the cover, so the Downloads screen works offline.
  final String? coverPath;

  final DownloadState state;

  /// 0..1.
  final double progress;

  /// Bytes saved so far.
  final int bytes;
  final String? error;

  /// When a download that lost the internet tries again.
  final DateTime? retryAt;
  final Map<String, Object?> source;
  final Map<String, Object?> result;

  static String idFor(DownloadKind kind, String groupKey, String itemKey) =>
      sha1
          .convert(utf8.encode('${kind.name}|$groupKey|$itemKey'))
          .toString()
          .substring(0, 20);

  bool get isDone => state == DownloadState.done;
  bool get isActive =>
      state == DownloadState.queued || state == DownloadState.running;

  /// The saved video (anime, movie).
  String? get videoPath => result['video'] as String?;

  /// Saved page files in reading order (manga).
  List<String> get pagePaths => [
    ...(result['pages'] as List? ?? const []).cast<String>(),
  ];

  List<SavedTrack> get subtitles => _tracks(result['subtitles']);
  List<SavedTrack> get audios => _tracks(result['audios']);

  static List<SavedTrack> _tracks(Object? raw) => [
    for (final t in (raw as List? ?? const []).cast<Map>())
      (path: t['path'] as String, lang: t['lang'] as String? ?? ''),
  ];

  DownloadItem copyWith({
    DownloadState? state,
    double? progress,
    int? bytes,
    String? error,
    bool clearError = false,
    DateTime? retryAt,
    bool clearRetry = false,
    String? coverPath,
    Map<String, Object?>? source,
    Map<String, Object?>? result,
  }) => DownloadItem(
    id: id,
    kind: kind,
    groupKey: groupKey,
    groupTitle: groupTitle,
    itemKey: itemKey,
    itemTitle: itemTitle,
    order: order,
    dir: dir,
    addedAt: addedAt,
    coverUrl: coverUrl,
    coverPath: coverPath ?? this.coverPath,
    state: state ?? this.state,
    progress: progress ?? this.progress,
    bytes: bytes ?? this.bytes,
    error: clearError ? null : (error ?? this.error),
    retryAt: clearRetry ? null : (retryAt ?? this.retryAt),
    source: source ?? this.source,
    result: result ?? this.result,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'groupKey': groupKey,
    'groupTitle': groupTitle,
    'itemKey': itemKey,
    'itemTitle': itemTitle,
    'order': order,
    'dir': dir,
    'addedAt': addedAt.toIso8601String(),
    'coverUrl': coverUrl,
    'coverPath': coverPath,
    'state': state.name,
    'progress': progress,
    'bytes': bytes,
    'error': error,
    'retryAt': retryAt?.toIso8601String(),
    'source': source,
    'result': result,
  };

  factory DownloadItem.fromJson(Map<String, dynamic> j) => DownloadItem(
    id: j['id'] as String,
    kind: DownloadKind.values.byName(j['kind'] as String),
    groupKey: j['groupKey'] as String,
    groupTitle: j['groupTitle'] as String? ?? '',
    itemKey: j['itemKey'] as String,
    itemTitle: j['itemTitle'] as String? ?? '',
    order: (j['order'] as num?)?.toDouble() ?? 0,
    dir: j['dir'] as String,
    addedAt: DateTime.parse(j['addedAt'] as String),
    coverUrl: j['coverUrl'] as String?,
    coverPath: j['coverPath'] as String?,
    state: DownloadState.values.byName(j['state'] as String),
    progress: (j['progress'] as num?)?.toDouble() ?? 0,
    bytes: (j['bytes'] as num?)?.toInt() ?? 0,
    error: j['error'] as String?,
    retryAt: DateTime.tryParse(j['retryAt'] as String? ?? ''),
    source: Map<String, Object?>.from(j['source'] as Map? ?? const {}),
    result: Map<String, Object?>.from(j['result'] as Map? ?? const {}),
  );
}

/// "1.4 GB", "820 MB", "12 KB".
String formatBytes(int bytes) {
  if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
  if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(0)} MB';
  return '${(bytes / 1024).ceil()} KB';
}
