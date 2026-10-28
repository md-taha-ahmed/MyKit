import 'package:flutter/services.dart';

import '../../domain/entities/track.dart';
import '../../domain/repositories/music_library_repository.dart';

/// Talks to `android/.../media/MediaLibraryChannel.kt`.
class MediaStoreDataSource {
  static const _channel = MethodChannel('com.mdtaha.mykit/media_library');
  static const _artCacheSize = 150;

  /// Small LRU so scrolling back doesn't reload covers. null = "no art".
  final _artCache = <String, Uint8List?>{};

  Future<bool> requestPermission() async =>
      await _channel.invokeMethod<bool>('requestPermission') ?? false;

  Future<void> openAppSettings() => _channel.invokeMethod('openSettings');

  Future<List<Track>> getTracks() async {
    try {
      final raw = await _channel.invokeListMethod<Map<Object?, Object?>>(
        'getTracks',
      );
      return (raw ?? []).map(_toTrack).toList();
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') throw const MusicPermissionDenied();
      rethrow;
    }
  }

  Future<Uint8List?> getArtwork(String uri, int size) async {
    final key = '$uri@$size';
    if (_artCache.containsKey(key)) {
      final hit = _artCache.remove(key);
      _artCache[key] = hit; // move to most-recent
      return hit;
    }
    Uint8List? bytes;
    try {
      bytes = await _channel.invokeMethod<Uint8List>('getArtwork', {
        'uri': uri,
        'size': size,
      });
    } on PlatformException {
      bytes = null;
    }
    _artCache[key] = bytes;
    if (_artCache.length > _artCacheSize) {
      _artCache.remove(_artCache.keys.first);
    }
    return bytes;
  }

  static Track _toTrack(Map<Object?, Object?> m) {
    final fileName = m['fileName'] as String? ?? '';
    final title = (m['title'] as String?)?.trim();
    return Track(
      id: m['id'] as String,
      uri: m['uri'] as String,
      title: title == null || title.isEmpty ? fileName : title,
      fileName: fileName,
      folderPath: m['folder'] as String? ?? 'Unknown',
      duration: Duration(milliseconds: (m['durationMs'] as num?)?.toInt() ?? 0),
      dateAdded: DateTime.fromMillisecondsSinceEpoch(
        (m['dateAdded'] as num?)?.toInt() ?? 0,
      ),
      artist: _clean(m['artist'] as String?),
      album: _clean(m['album'] as String?),
    );
  }

  /// MediaStore reports missing tags as `<unknown>`.
  static String? _clean(String? v) {
    if (v == null) return null;
    final t = v.trim();
    return t.isEmpty || t == '<unknown>' ? null : t;
  }
}
