import 'package:flutter/services.dart';

/// Direct stream URLs for a YouTube video.
class ShortStream {
  const ShortStream({
    required this.video,
    this.audio,
    this.width = 0,
    this.height = 0,
    this.fallback,
  });

  final String video;

  /// One file with video and audio (lower quality), if the pair fails.
  final String? fallback;

  /// Separate audio (YouTube serves HD video and audio apart).
  final String? audio;
  final int width;
  final int height;
}

/// Resolves YouTube Shorts to playable streams (`android/.../youtube/
/// YouTubeChannel.kt`, NewPipeExtractor). Results are cached natively, so
/// resolving the next Short ahead of time makes swiping instant.
class ShortsNativeDataSource {
  static const _channel = MethodChannel('com.mdtaha.mykit/youtube');

  /// Throws [PlatformException] if YouTube can't be read right now.
  Future<ShortStream> resolve(String videoId) async {
    final raw = await _channel.invokeMapMethod<String, Object?>('resolve', {
      'id': videoId,
    });
    final video = raw?['video'] as String?;
    if (video == null) {
      throw PlatformException(code: 'empty', message: 'No stream');
    }
    return ShortStream(
      video: video,
      audio: raw?['audio'] as String?,
      width: (raw?['width'] as num?)?.toInt() ?? 0,
      height: (raw?['height'] as num?)?.toInt() ?? 0,
      fallback: raw?['fallback'] as String?,
    );
  }

  /// Warms the native cache; errors are ignored.
  void prefetch(String videoId) => resolve(videoId).ignore();
}
