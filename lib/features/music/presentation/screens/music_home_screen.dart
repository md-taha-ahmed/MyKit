import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/i18n.dart';
import '../../domain/entities/track.dart';
import '../../domain/music_organizer.dart';
import '../../domain/repositories/music_library_repository.dart';
import '../../music_routes.dart';
import '../providers/music_providers.dart';
import '../widgets/music_widgets.dart';

/// Music folders on the device, A–Z.
class MusicHomeScreen extends ConsumerStatefulWidget {
  const MusicHomeScreen({super.key});

  @override
  ConsumerState<MusicHomeScreen> createState() => _MusicHomeScreenState();
}

class _MusicHomeScreenState extends ConsumerState<MusicHomeScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Retry after the user returns from system settings.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ref.read(musicLibraryProvider).error is MusicPermissionDenied) {
      ref.read(musicLibraryProvider.notifier).rescan();
    }
  }

  @override
  Widget build(BuildContext context) {
    final folders = ref.watch(musicFoldersProvider);
    final rescan = ref.read(musicLibraryProvider.notifier).rescan;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Music')),
        actions: [
          IconButton(
            tooltip: tr('Sort'),
            icon: const Icon(Icons.sort_by_alpha),
            onPressed: () => showMusicSortSheet(context),
          ),
          IconButton(
            tooltip: tr('Rescan device'),
            icon: const Icon(Icons.refresh),
            onPressed: rescan,
          ),
        ],
      ),
      body: folders.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => error is MusicPermissionDenied
            ? _Message(
                icon: Icons.lock_outline,
                title: tr('Allow access to your music'),
                message: tr(
                  'MyKit needs permission to read audio files on this device. Nothing leaves your phone.',
                ),
                actions: [
                  FilledButton(onPressed: rescan, child: Text(tr('Allow'))),
                  TextButton(
                    onPressed: ref
                        .read(musicLibraryRepositoryProvider)
                        .openAppSettings,
                    child: Text(tr('Open settings')),
                  ),
                ],
              )
            : _Message(
                icon: Icons.error_outline,
                title: tr('Could not read your music'),
                message: '$error',
                actions: [
                  FilledButton(onPressed: rescan, child: Text(tr('Retry'))),
                ],
              ),
        data: (folders) => folders.isEmpty
            ? _Message(
                icon: Icons.library_music_outlined,
                title: tr('No music found'),
                message: tr(
                  'Copy audio files (MP3, M4A, FLAC, …) to your phone, then tap refresh.',
                ),
                actions: [
                  FilledButton(onPressed: rescan, child: Text(tr('Rescan'))),
                ],
              )
            : RefreshIndicator(
                onRefresh: rescan,
                child: _FolderList(folders: folders),
              ),
      ),
      bottomNavigationBar: const MiniPlayer(),
    );
  }
}

class _FolderList extends ConsumerWidget {
  const _FolderList({required this.folders});

  final List<MusicFolder> folders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = folders.fold<int>(0, (n, f) => n + f.tracks.length);
    final player = ref.read(musicPlayerProvider);
    final nameSource = ref.watch(musicSortProvider).nameSource;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _FolderTile(
          icon: Icons.library_music,
          name: tr('All songs'),
          subtitle: tr('{total} songs', {'total': total}),
          onTap: () => context.push(MusicRoutes.folder(allSongsFolder)),
          onShuffle: () => player.playTracks(
            ref.read(folderTracksProvider(allSongsFolder)),
            shuffle: true,
            nameSource: nameSource,
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            tr('FOLDERS'),
            style: TextStyle(
              color: musicAccent,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ),
        for (final f in folders)
          _FolderTile(
            icon: Icons.folder,
            name: f.name,
            subtitle:
                '${f.tracks.length} ${f.tracks.length == 1 ? 'song' : 'songs'}'
                ' · ${MusicOrganizer.friendlyPath(f.path)}',
            onTap: () => context.push(MusicRoutes.folder(f.path)),
            onShuffle: () => player.playTracks(
              f.tracks,
              shuffle: true,
              nameSource: nameSource,
            ),
          ),
      ],
    );
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.icon,
    required this.name,
    required this.subtitle,
    required this.onTap,
    required this.onShuffle,
  });

  final IconData icon;
  final String name;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: musicAccent.withValues(alpha: .15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: musicAccent),
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white54),
      ),
      trailing: IconButton(
        tooltip: tr('Shuffle'),
        icon: const Icon(Icons.shuffle),
        onPressed: onShuffle,
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.message,
    this.actions = const [],
  });

  final IconData icon;
  final String title;
  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.white24),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 20),
            ...actions,
          ],
        ),
      ),
    );
  }
}
