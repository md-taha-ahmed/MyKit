import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../manga/domain/entities/anime_entities.dart';
import '../../../manga/domain/entities/manga_entities.dart';
import '../../../manga/manga_routes.dart';
import '../../../manga/presentation/providers/anime_providers.dart';
import '../../../manga/presentation/providers/manga_providers.dart';
import '../../../movies/domain/entities/stremio_entities.dart';
import '../../../movies/movies_routes.dart';
import '../../../movies/presentation/screens/player_screen.dart';
import '../../domain/download_item.dart';
import '../providers/downloads_providers.dart';

/// One line about where a download is at.
String downloadStatusText(DownloadItem item) {
  final pct = '${(item.progress * 100).round()}%';
  final size = item.bytes > 0 ? formatBytes(item.bytes) : null;
  return switch (item.state) {
    DownloadState.done => [tr('Saved for offline'), ?size].join(' · '),
    DownloadState.running => [pct, ?size].join(' · '),
    DownloadState.queued =>
      item.error ??
          (item.progress > 0
              ? tr('Waiting · {pct}', {'pct': pct})
              : tr('Waiting')),
    DownloadState.paused => tr('Paused · {pct}', {'pct': pct}),
    DownloadState.failed => item.error ?? tr('Download failed'),
  };
}

/// The download icon on a chapter, episode or source: starts a download, or
/// shows how it's going (tap for pause, resume, delete).
class DownloadButton extends ConsumerWidget {
  const DownloadButton({
    super.key,
    required this.id,
    required this.onDownload,
    this.accent,
  });

  final String id;
  final VoidCallback onDownload;
  final Color? accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(downloadForProvider(id));
    if (item == null) {
      return IconButton(
        tooltip: tr('Download for offline'),
        icon: const Icon(Icons.download_outlined, color: Colors.white54),
        onPressed: onDownload,
      );
    }
    return IconButton(
      tooltip: downloadStatusText(item),
      icon: DownloadStateIcon(item: item, accent: accent),
      onPressed: () => showDownloadActions(context, ref, item),
    );
  }
}

class DownloadStateIcon extends StatelessWidget {
  const DownloadStateIcon({super.key, required this.item, this.accent});

  final DownloadItem item;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? Theme.of(context).colorScheme.primary;
    return switch (item.state) {
      DownloadState.done => Icon(Icons.download_done, color: color),
      DownloadState.running => SizedBox.square(
        dimension: 22,
        child: CircularProgressIndicator(
          value: item.progress > 0.01 ? item.progress : null,
          strokeWidth: 2.5,
          color: color,
        ),
      ),
      DownloadState.queued =>
        item.retryAt != null
            ? const Icon(Icons.wifi_off, color: Colors.orangeAccent)
            : const Icon(Icons.schedule, color: Colors.white54),
      DownloadState.paused => const Icon(
        Icons.pause_circle_outline,
        color: Colors.white54,
      ),
      DownloadState.failed => const Icon(
        Icons.error_outline,
        color: Colors.orangeAccent,
      ),
    };
  }
}

Future<void> showDownloadActions(
  BuildContext context,
  WidgetRef ref,
  DownloadItem item,
) async {
  final notifier = ref.read(downloadsProvider.notifier);
  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              [
                item.groupTitle,
                if (item.itemTitle.isNotEmpty) item.itemTitle,
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(downloadStatusText(item)),
          ),
          if (item.isDone)
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: Text(
                item.kind == DownloadKind.manga ? tr('Read') : tr('Play'),
              ),
              onTap: () => Navigator.pop(context, 'open'),
            ),
          if (item.isActive)
            ListTile(
              leading: const Icon(Icons.pause),
              title: Text(tr('Pause')),
              onTap: () => Navigator.pop(context, 'pause'),
            ),
          if (item.state == DownloadState.paused ||
              item.state == DownloadState.failed ||
              item.retryAt != null)
            ListTile(
              leading: const Icon(Icons.refresh),
              title: Text(
                item.state == DownloadState.paused
                    ? tr('Resume')
                    : tr('Try again now'),
              ),
              onTap: () => Navigator.pop(context, 'resume'),
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(
              item.isDone ? tr('Delete download') : tr('Cancel download'),
            ),
            onTap: () => Navigator.pop(context, 'delete'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  switch (action) {
    case 'open':
      openDownload(context, ref, item);
    case 'pause':
      notifier.pause(item.id);
    case 'resume':
      notifier.resume(item.id);
    case 'delete':
      await notifier.delete(item.id);
  }
}

/// Reads or plays a finished download (no internet needed).
void openDownload(BuildContext context, WidgetRef ref, DownloadItem item) {
  final router = GoRouter.of(context);
  switch (item.kind) {
    case DownloadKind.manga:
      final sourceId = item.source['sourceId'] as String;
      final manga = Manga.fromMap(sourceId, item.source['manga'] as Map);
      // The reader looks the title up here; offline, nothing else put it there.
      if (ref.read(mangaCacheProvider)[manga.key] == null) {
        ref.read(mangaCacheProvider.notifier).put(manga);
      }
      router.push(MangaRoutes.reader(item.groupKey, item.itemKey));
    case DownloadKind.anime:
      final anime = Anime.fromJson(
        Map<String, dynamic>.from(item.source['anime'] as Map),
      );
      if (ref.read(animeCacheProvider)[anime.key] == null) {
        ref.read(animeCacheProvider.notifier).put(anime);
      }
      ref
          .read(animeLibraryProvider.notifier)
          .recordEpisode(anime, item.itemKey);
      router.push(MoviesRoutes.play, extra: playerArgsForDownload(item));
    case DownloadKind.movie:
      router.push(MoviesRoutes.play, extra: playerArgsForDownload(item));
  }
}

/// Player settings for a saved video: the local file and its saved tracks.
/// Same ids as playing it online, so watch progress is shared.
PlayerArgs playerArgsForDownload(DownloadItem item) {
  final src = item.source;
  final subtitles = [
    for (final s in item.subtitles)
      SubtitleInfo(
        id: s.path,
        url: s.path,
        lang: s.lang,
        addonName: tr('Downloaded'),
      ),
  ];
  final audios = [for (final a in item.audios) (url: a.path, lang: a.lang)];
  if (item.kind == DownloadKind.anime) {
    final anime = src['anime'] as Map;
    return PlayerArgs(
      source: StreamSource(
        addonName: tr('Downloaded'),
        name: src['videoTitle'] as String? ?? '',
        title: '',
        url: item.videoPath,
      ),
      type: 'anime',
      metaId: item.groupKey,
      videoId: 'anime:${anime['sourceId']}:${item.itemKey}',
      name: item.groupTitle,
      episodeLabel: item.itemTitle,
      subtitles: subtitles,
      audioTracks: audios,
    );
  }
  return PlayerArgs(
    source: StreamSource(
      addonName: tr('Downloaded'),
      name: src['release'] as String? ?? '',
      title: '',
      url: item.videoPath,
    ),
    type: src['type'] as String,
    metaId: item.groupKey,
    videoId: item.itemKey,
    name: item.groupTitle,
    poster: src['poster'] as String?,
    background: src['background'] as String?,
    episodeLabel: src['episodeLabel'] as String?,
    // None saved: ask the subtitle add-ons (works when online).
    subtitles: subtitles.isEmpty ? null : subtitles,
    audioTracks: audios,
  );
}
