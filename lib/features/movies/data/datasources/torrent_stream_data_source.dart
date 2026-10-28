import 'package:flutter/services.dart';

import '../../domain/entities/stremio_entities.dart';
import '../../domain/entities/torrent_stream_status.dart';
import '../../domain/repositories/movies_repository.dart';

/// Talks to the native torrent engine
/// (`android/.../torrent/TorrentChannel.kt` + `TorrentStreamEngine.kt`).
class TorrentStreamDataSource {
  static const _channel = MethodChannel('com.mdtaha.mykit/torrent');

  /// Public trackers added to every magnet so peers are found quickly.
  static const _extraTrackers = [
    'udp://tracker.opentrackr.org:1337/announce',
    'udp://open.stealth.si:80/announce',
    'udp://open.demonii.com:1337/announce',
    'udp://tracker.torrent.eu.org:451/announce',
    'udp://exodus.desync.com:6969/announce',
    'udp://tracker.openbittorrent.com:6969/announce',
  ];

  Future<T?> _call<T>(String method, Map<String, Object?> args) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw MoviesException(e.message ?? e.code);
    }
  }

  Future<TorrentStreamStatus> start(StreamSource source) async {
    final raw = await _call<Map<Object?, Object?>>('start', {
      'infoHash': source.infoHash,
      'fileIdx': source.fileIdx,
      'trackers': {...source.trackers, ..._extraTrackers}.toList(),
      'filename': source.filename,
    });
    return TorrentStreamStatus.fromMap(raw!);
  }

  Future<TorrentStreamStatus?> status(String id) async {
    final raw = await _call<Map<Object?, Object?>>('status', {'id': id});
    return raw == null ? null : TorrentStreamStatus.fromMap(raw);
  }

  Future<void> stop(String id) => _call<void>('stop', {'id': id});

  /// Starts the engine (DHT, trackers) before the first stream is needed.
  Future<void> warmUp() => _call<void>('warmUp', const {});
}
