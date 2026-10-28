import 'dart:math';

import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../../domain/entities/track.dart';

/// Single app-wide player. Background playback, the media notification and
/// lock-screen/headset controls come from `just_audio_background`, which is
/// initialised in `main()`.
class MusicPlayerService {
  MusicPlayerService() : player = AudioPlayer();

  final AudioPlayer player;

  /// Replaces the queue with [tracks] and starts playing.
  Future<void> playTracks(
    List<Track> tracks, {
    int index = 0,
    bool shuffle = false,
    TrackNameSource nameSource = TrackNameSource.title,
  }) async {
    if (tracks.isEmpty) return;
    final start = shuffle && index == 0
        ? Random().nextInt(tracks.length)
        : index;

    await player.setShuffleModeEnabled(false);
    await player.setAudioSources(
      [for (final t in tracks) _source(t, nameSource)],
      initialIndex: start,
      initialPosition: Duration.zero,
    );
    if (shuffle) {
      await player.shuffle();
      await player.setShuffleModeEnabled(true);
    }
    // Not awaited: play() completes only when playback pauses/stops.
    player.play();
  }

  Future<void> togglePlay() async =>
      player.playing ? player.pause() : player.play();

  Future<void> next() => player.seekToNext();

  /// Restarts the song if past 3s, otherwise goes to the previous one.
  Future<void> previous() async {
    if (player.position > const Duration(seconds: 3) || !player.hasPrevious) {
      await player.seek(Duration.zero);
    } else {
      await player.seekToPrevious();
    }
  }

  Future<void> seek(Duration position) => player.seek(position);

  /// Plays the queued song with media [id] (queue may be shown shuffled).
  Future<void> jumpToId(String id) async {
    final index = player.sequence.indexWhere(
      (s) => (s.tag as MediaItem).id == id,
    );
    if (index < 0) return;
    await player.seek(Duration.zero, index: index);
    if (!player.playing) player.play();
  }

  Future<void> toggleShuffle() async {
    final enable = !player.shuffleModeEnabled;
    if (enable) await player.shuffle();
    await player.setShuffleModeEnabled(enable);
  }

  /// off → all → one → off
  Future<void> cycleRepeat() => player.setLoopMode(switch (player.loopMode) {
    LoopMode.off => LoopMode.all,
    LoopMode.all => LoopMode.one,
    LoopMode.one => LoopMode.off,
  });

  Future<void> dispose() => player.dispose();

  static AudioSource _source(Track t, TrackNameSource nameSource) {
    return AudioSource.uri(
      Uri.parse(t.uri),
      tag: MediaItem(
        id: t.id,
        title: t.displayName(nameSource),
        artist: t.artist,
        album: t.album,
        duration: t.duration,
        // Notification art: embedded cover read via ContentResolver.loadThumbnail.
        artUri: Uri.parse(t.uri),
        extras: const {'loadThumbnailUri': 'true'},
      ),
    );
  }
}
