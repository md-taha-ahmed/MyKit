/// Progress of a torrent being streamed (see `TorrentStreamEngine.kt`).
class TorrentStreamStatus {
  const TorrentStreamStatus({
    required this.id,
    required this.state,
    this.error,
    this.url,
    this.fileName = '',
    this.fileSize = 0,
    this.buffer = 0,
    this.progress = 0,
    this.downloadRate = 0,
    this.peers = 0,
    this.seeds = 0,
  });

  final String id;

  /// `metadata` → `buffering` → `ready`, or `error`.
  final String state;
  final String? error;

  /// Local HTTP URL the player opens (once the file is known).
  final String? url;
  final String fileName;
  final int fileSize;

  /// Prebuffer progress, 0..1.
  final double buffer;

  /// Whole-file download progress, 0..1.
  final double progress;

  /// Bytes per second.
  final int downloadRate;
  final int peers;
  final int seeds;

  bool get ready => state == 'ready';
  bool get failed => state == 'error';

  factory TorrentStreamStatus.fromMap(Map<Object?, Object?> m) =>
      TorrentStreamStatus(
        id: m['id'] as String,
        state: m['state'] as String,
        error: m['error'] as String?,
        url: m['url'] as String?,
        fileName: (m['fileName'] as String?) ?? '',
        fileSize: (m['fileSize'] as num?)?.toInt() ?? 0,
        buffer: (m['buffer'] as num?)?.toDouble() ?? 0,
        progress: (m['progress'] as num?)?.toDouble() ?? 0,
        downloadRate: (m['downloadRate'] as num?)?.toInt() ?? 0,
        peers: (m['peers'] as num?)?.toInt() ?? 0,
        seeds: (m['seeds'] as num?)?.toInt() ?? 0,
      );
}
