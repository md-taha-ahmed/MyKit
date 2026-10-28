import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/music_organizer.dart';
import '../providers/music_providers.dart';
import '../widgets/music_widgets.dart';

/// Songs in one folder (or all songs), sorted by the chosen order.
class MusicFolderScreen extends ConsumerWidget {
  const MusicFolderScreen({super.key, required this.path});

  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(folderTracksProvider(path));
    final settings = ref.watch(musicSortProvider);
    final player = ref.read(musicPlayerProvider);
    final isAll = path == allSongsFolder;
    final total = tracks.fold(Duration.zero, (sum, t) => sum + t.duration);

    void play(int index, {bool shuffle = false}) => player.playTracks(
      tracks,
      index: index,
      shuffle: shuffle,
      nameSource: settings.nameSource,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(isAll ? 'All songs' : MusicOrganizer.folderName(path)),
        actions: [
          IconButton(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort_by_alpha),
            onPressed: () => showMusicSortSheet(context),
          ),
        ],
      ),
      body: tracks.isEmpty
          ? const Center(child: Text('No songs in this folder.'))
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: tracks.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return _Header(
                    subtitle: [
                      if (!isAll) MusicOrganizer.friendlyPath(path),
                      '${tracks.length} songs · ${formatDuration(total)}',
                      settings.sort.label,
                    ].join('\n'),
                    onPlay: () => play(0),
                    onShuffle: () => play(0, shuffle: true),
                  );
                }
                final index = i - 1;
                return TrackTile(
                  track: tracks[index],
                  nameSource: settings.nameSource,
                  onTap: () => play(index),
                );
              },
            ),
      bottomNavigationBar: const MiniPlayer(),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.subtitle,
    required this.onPlay,
    required this.onShuffle,
  });

  final String subtitle;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white54, height: 1.4),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: musicAccent),
                  onPressed: onPlay,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onShuffle,
                  icon: const Icon(Icons.shuffle),
                  label: const Text('Shuffle'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
