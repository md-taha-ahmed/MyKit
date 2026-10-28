import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';

import '../../domain/entities/track.dart';
import '../../music_routes.dart';
import '../providers/music_providers.dart';

const musicAccent = Color(0xFF1DB9A0);

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// Embedded cover art, or a music-note placeholder.
class TrackArtwork extends ConsumerWidget {
  const TrackArtwork({
    super.key,
    required this.uri,
    this.size = 48,
    this.radius = 8,
  });

  final String? uri;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = uri == null
        ? null
        : ref.watch(trackArtworkProvider(uri!)).value;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox.square(
        dimension: size,
        child: bytes != null
            ? Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true)
            : DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2D4F4A), Color(0xFF1B2A33)],
                  ),
                ),
                child: Icon(
                  Icons.music_note,
                  color: Colors.white54,
                  size: size * .45,
                ),
              ),
      ),
    );
  }
}

class TrackTile extends ConsumerWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.nameSource,
    required this.onTap,
  });

  final Track track;
  final TrackNameSource nameSource;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(nowPlayingProvider).value?.id == track.id;
    final playing = ref.watch(playerStateProvider).value?.playing ?? false;
    final subtitle = [
      track.artist ?? 'Unknown artist',
      formatDuration(track.duration),
    ].join(' · ');

    return ListTile(
      onTap: onTap,
      leading: Stack(
        alignment: Alignment.center,
        children: [
          TrackArtwork(uri: track.uri),
          if (current)
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                playing ? Icons.graphic_eq : Icons.pause,
                color: musicAccent,
              ),
            ),
        ],
      ),
      title: Text(
        track.displayName(nameSource),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: current ? musicAccent : null,
          fontWeight: current ? FontWeight.w600 : null,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white54),
      ),
    );
  }
}

/// Compact player shown at the bottom of music screens.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(nowPlayingProvider).value;
    if (item == null) return const SizedBox.shrink();

    final service = ref.read(musicPlayerProvider);
    final state = ref.watch(playerStateProvider).value;
    final playing = state?.playing ?? false;
    final loading =
        state?.processingState == ProcessingState.loading ||
        state?.processingState == ProcessingState.buffering;
    final position = ref.watch(playbackPositionProvider).value ?? Duration.zero;
    final total = ref.watch(playbackDurationProvider).value ?? item.duration;
    final progress = total == null || total.inMilliseconds == 0
        ? 0.0
        : (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

    return Material(
      color: const Color(0xFF2A2A2D),
      child: SafeArea(
        top: false,
        child: InkWell(
          onTap: () => context.push(MusicRoutes.nowPlaying),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value: progress,
                minHeight: 2,
                color: musicAccent,
                backgroundColor: Colors.white10,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                child: Row(
                  children: [
                    Hero(
                      tag: 'now-playing-art',
                      child: TrackArtwork(
                        uri: item.artUri?.toString(),
                        size: 44,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            item.artist ?? 'Unknown artist',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      iconSize: 32,
                      onPressed: loading ? null : service.togglePlay,
                      icon: Icon(
                        playing
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_filled,
                      ),
                    ),
                    IconButton(
                      onPressed: service.next,
                      icon: const Icon(Icons.skip_next),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sort order + naming options.
Future<void> showMusicSortSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => Consumer(
      builder: (context, ref, _) {
        final settings = ref.watch(musicSortProvider);
        final notifier = ref.read(musicSortProvider.notifier);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SheetHeader('Sort songs by'),
                RadioGroup<TrackSort>(
                  groupValue: settings.sort,
                  onChanged: (v) => v == null ? null : notifier.setSort(v),
                  child: Column(
                    children: [
                      for (final s in TrackSort.values)
                        RadioListTile<TrackSort>(
                          value: s,
                          title: Text(s.label),
                        ),
                    ],
                  ),
                ),
                const _SheetHeader('Show and sort by'),
                RadioGroup<TrackNameSource>(
                  groupValue: settings.nameSource,
                  onChanged: (v) =>
                      v == null ? null : notifier.setNameSource(v),
                  child: Column(
                    children: [
                      for (final s in TrackNameSource.values)
                        RadioListTile<TrackNameSource>(
                          value: s,
                          title: Text(s.label),
                        ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text(
                    'Folders are always listed A–Z.',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
    child: Text(
      text,
      style: const TextStyle(color: musicAccent, fontWeight: FontWeight.w600),
    ),
  );
}
