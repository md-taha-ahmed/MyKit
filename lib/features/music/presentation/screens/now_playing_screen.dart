import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../../core/i18n/i18n.dart';
import '../providers/music_providers.dart';
import '../widgets/music_widgets.dart';

/// Full-screen player.
class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(nowPlayingProvider).value;
    if (item == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(tr('Nothing is playing.'))),
      );
    }

    final service = ref.read(musicPlayerProvider);
    final state = ref.watch(playerStateProvider).value;
    final playing = state?.playing ?? false;
    final shuffle = ref.watch(shuffleEnabledProvider).value ?? false;
    final loop = ref.watch(loopModeProvider).value ?? LoopMode.off;
    final artSize = MediaQuery.sizeOf(context).width - 64;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down, size: 32),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(tr('Now playing'), style: TextStyle(fontSize: 16)),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: tr('Queue'),
            icon: const Icon(Icons.queue_music),
            onPressed: () => _showQueue(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(),
              Hero(
                tag: 'now-playing-art',
                child: TrackArtwork(
                  uri: item.artUri?.toString(),
                  size: artSize.clamp(160, 360),
                  radius: 20,
                ),
              ),
              const Spacer(),
              Text(
                item.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                [item.artist ?? tr('Unknown artist'), ?item.album].join(' · '),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 20),
              _SeekBar(fallbackDuration: item.duration),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    tooltip: tr('Shuffle'),
                    onPressed: service.toggleShuffle,
                    icon: Icon(
                      Icons.shuffle,
                      color: shuffle ? musicAccent : Colors.white54,
                    ),
                  ),
                  IconButton(
                    iconSize: 40,
                    onPressed: service.previous,
                    icon: const Icon(Icons.skip_previous),
                  ),
                  IconButton.filled(
                    iconSize: 44,
                    style: IconButton.styleFrom(
                      backgroundColor: musicAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.all(14),
                    ),
                    onPressed: service.togglePlay,
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  ),
                  IconButton(
                    iconSize: 40,
                    onPressed: service.next,
                    icon: const Icon(Icons.skip_next),
                  ),
                  IconButton(
                    tooltip: switch (loop) {
                      LoopMode.off => tr('Repeat off'),
                      LoopMode.all => tr('Repeat all'),
                      LoopMode.one => tr('Repeat one'),
                    },
                    onPressed: service.cycleRepeat,
                    icon: Icon(
                      loop == LoopMode.one ? Icons.repeat_one : Icons.repeat,
                      color: loop == LoopMode.off
                          ? Colors.white54
                          : musicAccent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _showQueue(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .6,
        maxChildSize: .95,
        builder: (context, controller) => Consumer(
          builder: (context, ref, _) {
            final queue = ref.watch(playQueueProvider).value ?? const [];
            final currentId = ref.watch(nowPlayingProvider).value?.id;
            return ListView.builder(
              controller: controller,
              itemCount: queue.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text(
                      tr('Up next · {length} songs', {'length': queue.length}),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  );
                }
                final item = queue[i - 1];
                final current = item.id == currentId;
                return ListTile(
                  leading: TrackArtwork(uri: item.artUri?.toString(), size: 40),
                  title: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: current ? musicAccent : null),
                  ),
                  subtitle: Text(
                    item.artist ?? tr('Unknown artist'),
                    maxLines: 1,
                    style: const TextStyle(color: Colors.white54),
                  ),
                  trailing: current
                      ? const Icon(Icons.graphic_eq, color: musicAccent)
                      : null,
                  onTap: () => ref.read(musicPlayerProvider).jumpToId(item.id),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Slider that follows playback but doesn't fight the user's finger.
class _SeekBar extends ConsumerStatefulWidget {
  const _SeekBar({this.fallbackDuration});

  final Duration? fallbackDuration;

  @override
  ConsumerState<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends ConsumerState<_SeekBar> {
  double? _dragMs;

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(playbackPositionProvider).value ?? Duration.zero;
    final total =
        ref.watch(playbackDurationProvider).value ??
        widget.fallbackDuration ??
        Duration.zero;
    final maxMs = total.inMilliseconds.toDouble();
    final valueMs = (_dragMs ?? position.inMilliseconds.toDouble()).clamp(
      0.0,
      maxMs <= 0 ? 0.0 : maxMs,
    );

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            activeTrackColor: musicAccent,
            thumbColor: musicAccent,
            inactiveTrackColor: Colors.white12,
            overlayShape: SliderComponentShape.noOverlay,
          ),
          child: Slider(
            max: maxMs <= 0 ? 1 : maxMs,
            value: maxMs <= 0 ? 0 : valueMs,
            onChanged: maxMs <= 0 ? null : (v) => setState(() => _dragMs = v),
            onChangeEnd: (v) {
              ref
                  .read(musicPlayerProvider)
                  .seek(Duration(milliseconds: v.round()));
              setState(() => _dragMs = null);
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              formatDuration(Duration(milliseconds: valueMs.round())),
              style: const TextStyle(color: Colors.white54, fontSize: 12.5),
            ),
            Text(
              formatDuration(total),
              style: const TextStyle(color: Colors.white54, fontSize: 12.5),
            ),
          ],
        ),
      ],
    );
  }
}
