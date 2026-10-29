import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../movies/domain/entities/stremio_entities.dart';
import '../../../movies/movies_routes.dart';
import '../../../movies/presentation/providers/movies_providers.dart';
import '../../../movies/presentation/screens/player_screen.dart';
import '../../domain/entities/anime_entities.dart';
import '../../domain/entities/manga_entities.dart';
import '../providers/anime_providers.dart';
import '../widgets/anime_widgets.dart';
import '../widgets/manga_widgets.dart';

/// Anime details with episodes (or seasons), watched marks and playback.
class AnimeDetailsScreen extends ConsumerWidget {
  const AnimeDetailsScreen({super.key, required this.animeKey});

  final String animeKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cached = ref.watch(animeCacheProvider)[animeKey];
    if (cached == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This title is no longer available.')),
      );
    }
    final details = ref.watch(animeDetailsProvider(animeKey));
    final anime = details.value ?? cached;
    final inLibrary = ref.watch(
      animeLibraryProvider.select((l) => l.any((e) => e.anime.key == animeKey)),
    );
    final seasons = anime.fetchType == AnimeFetchType.seasons;

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Open in browser',
            icon: const Icon(Icons.public),
            onPressed: () async {
              final url = await ref.read(animeRepositoryProvider).webUrl(anime);
              if (url != null) {
                await launchUrl(
                  Uri.parse(url),
                  mode: LaunchMode.externalApplication,
                );
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(animeDetailsProvider(animeKey));
          ref.invalidate(animeEpisodesProvider(animeKey));
          ref.invalidate(animeSeasonsProvider(animeKey));
          await ref.read(animeDetailsProvider(animeKey).future);
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _Header(
                anime: anime,
                loading: details.isLoading,
                inLibrary: inLibrary,
              ),
            ),
            // Episodes load alongside details (slow sites shouldn't block them).
            if (seasons)
              _SeasonsSliver(animeKey: animeKey)
            else
              _EpisodesSliver(anime: anime),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({
    required this.anime,
    required this.loading,
    required this.inLibrary,
  });

  final Anime anime;
  final bool loading;
  final bool inLibrary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(animeSourceProvider(anime.sourceId));
    final status = MangaStatus.of(anime.status);
    final people = {
      anime.author,
      anime.artist,
    }.whereType<String>().where((s) => s.isNotEmpty).join(', ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 110, child: AnimeCover(anime: anime)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      anime.title,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (people.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        people,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (status != MangaStatus.unknown) status.label,
                        if (source != null) source.name,
                      ].join(' · '),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(animeLibraryProvider.notifier).toggle(anime),
                  icon: Icon(
                    inLibrary ? Icons.favorite : Icons.favorite_border,
                    color: inLibrary ? mangaAccent : null,
                  ),
                  label: Text(inLibrary ? 'In library' : 'Add to library'),
                ),
              ),
            ],
          ),
          if (anime.description?.isNotEmpty ?? false) ...[
            const SizedBox(height: 12),
            Text(
              anime.description!,
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
          ],
          if (anime.genres.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final g in anime.genres)
                  Chip(
                    label: Text(g, style: const TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
          if (loading) const LinearProgressIndicator(minHeight: 2),
        ],
      ),
    );
  }
}

class _SeasonsSliver extends ConsumerWidget {
  const _SeasonsSliver({required this.animeKey});

  final String animeKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(animeSeasonsProvider(animeKey))
        .when(
          loading: () => const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (e, _) => SliverToBoxAdapter(
            child: MangaErrorView(
              error: e,
              onRetry: () => ref.invalidate(animeSeasonsProvider(animeKey)),
            ),
          ),
          data: (seasons) => SliverPadding(
            padding: const EdgeInsets.all(12),
            sliver: SliverGrid.builder(
              gridDelegate: mangaGridDelegate,
              itemCount: seasons.length,
              itemBuilder: (_, i) => AnimeGridCard(anime: seasons[i]),
            ),
          ),
        );
  }
}

class _EpisodesSliver extends ConsumerWidget {
  const _EpisodesSliver({required this.anime});

  final Anime anime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuilds on library changes (incl. progress for titles not in it).
    ref.watch(animeLibraryProvider);
    final progress = ref
        .read(animeLibraryProvider.notifier)
        .progressFor(anime.key);
    final history = ref.watch(watchHistoryProvider);

    return ref
        .watch(animeEpisodesProvider(anime.key))
        .when(
          loading: () => const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (e, _) => SliverToBoxAdapter(
            child: MangaErrorView(
              error: e,
              onRetry: () => ref.invalidate(animeEpisodesProvider(anime.key)),
            ),
          ),
          data: (episodes) {
            if (episodes.isEmpty) {
              return const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      'No episodes yet.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                ),
              );
            }
            final last = progress?.lastEpisodeUrl;
            final lastEpisode = episodes
                .where((e) => e.url == last)
                .firstOrNull;
            return SliverList.list(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      Text(
                        '${episodes.length} episodes',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: mangaAccent,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => playEpisode(
                          context,
                          ref,
                          anime,
                          lastEpisode ??
                              // Sources list newest first; start at episode 1.
                              episodes.last,
                        ),
                        icon: const Icon(Icons.play_arrow),
                        label: Text(lastEpisode != null ? 'Continue' : 'Start'),
                      ),
                    ],
                  ),
                ),
                for (final ep in episodes)
                  _EpisodeTile(
                    anime: anime,
                    episode: ep,
                    current: ep.url == last,
                    watch: history
                        .where((h) => h.videoId == _videoId(anime, ep))
                        .firstOrNull,
                    watched:
                        progress?.watchedEpisodes.contains(ep.url) ?? false,
                  ),
              ],
            );
          },
        );
  }
}

String _videoId(Anime anime, AnimeEpisode ep) =>
    'anime:${anime.sourceId}:${ep.url}';

class _EpisodeTile extends ConsumerWidget {
  const _EpisodeTile({
    required this.anime,
    required this.episode,
    required this.current,
    required this.watched,
    this.watch,
  });

  final Anime anime;
  final AnimeEpisode episode;
  final bool current;
  final bool watched;
  final WatchEntry? watch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seen = watched || (watch?.finished ?? false);
    final date = episode.dateUpload > 0
        ? DateFormat.yMMMd().format(
            DateTime.fromMillisecondsSinceEpoch(episode.dateUpload),
          )
        : null;
    final subtitle = [
      ?date,
      if (episode.scanlator?.isNotEmpty ?? false) episode.scanlator!,
      if (episode.filler) 'Filler',
      if (watch != null && !seen)
        '${_fmt(watch!.position)} / ${_fmt(watch!.duration)}',
    ].join(' · ');

    return ListTile(
      onTap: () => playEpisode(context, ref, anime, episode),
      onLongPress: () => ref
          .read(animeLibraryProvider.notifier)
          .setWatched(anime, episode.url, !seen),
      leading: Icon(
        seen
            ? Icons.check_circle
            : current
            ? Icons.play_circle_outline
            : Icons.circle_outlined,
        color: seen
            ? Colors.white38
            : current
            ? mangaAccent
            : Colors.white38,
      ),
      title: Text(
        episode.name,
        style: TextStyle(color: seen ? Colors.white54 : null),
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }
}

// ---------------------------------------------------------------------------
// Playback: pick a video (hoster / quality), resolve it, open the player.
// ---------------------------------------------------------------------------

Future<void> playEpisode(
  BuildContext context,
  WidgetRef ref,
  Anime anime,
  AnimeEpisode episode,
) async {
  final picked = await showModalBottomSheet<AnimeVideo>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _VideoPicker(anime: anime, episode: episode),
  );
  if (picked == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
  final ResolvedVideo video;
  try {
    video = await ref
        .read(animeRepositoryProvider)
        .resolve(anime.sourceId, picked.token);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not play: $e')));
    return;
  }
  ref.read(animeLibraryProvider.notifier).recordEpisode(anime, episode.url);
  final source = ref.read(animeSourceProvider(anime.sourceId));
  router.push(
    MoviesRoutes.play,
    extra: PlayerArgs(
      source: StreamSource(
        addonName: source?.name ?? 'Anime',
        name: picked.title,
        title: '',
        url: video.url,
      ),
      type: 'anime',
      metaId: anime.key,
      videoId: _videoId(anime, episode),
      name: anime.title,
      episodeLabel: episode.name,
      httpHeaders: video.headers,
      subtitles: [
        for (final s in video.subtitles)
          SubtitleInfo(
            id: s.url,
            url: s.url,
            lang: s.lang,
            addonName: source?.name ?? 'Source',
          ),
      ],
      audioTracks: video.audios,
    ),
  );
}

class _VideoPicker extends ConsumerStatefulWidget {
  const _VideoPicker({required this.anime, required this.episode});

  final Anime anime;
  final AnimeEpisode episode;

  @override
  ConsumerState<_VideoPicker> createState() => _VideoPickerState();
}

class _VideoPickerState extends ConsumerState<_VideoPicker> {
  late final Future<List<AnimeHoster>> _hosters = ref
      .read(animeRepositoryProvider)
      .hosters(widget.anime.sourceId, widget.episode);

  /// Videos of hosters loaded on demand (lazy ones).
  final _loaded = <String, Future<List<AnimeVideo>>>{};

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.75,
      ),
      child: SafeArea(
        child: FutureBuilder<List<AnimeHoster>>(
          future: _hosters,
          builder: (context, snap) {
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load videos: ${snap.error}',
                  textAlign: TextAlign.center,
                ),
              );
            }
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Finding videos…'),
                  ],
                ),
              );
            }
            final hosters = snap.data!;
            final videos = [for (final h in hosters) ...?h.videos];
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                ListTile(
                  title: Text(
                    widget.episode.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('Choose a video'),
                ),
                if (videos.isEmpty && hosters.every((h) => !h.lazy))
                  const ListTile(
                    title: Text(
                      'No videos found for this episode.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                for (final h in hosters) ...[
                  if (h.name != null) SectionLabel(h.name!),
                  if (h.videos != null)
                    for (final v in h.videos!)
                      // Sources sort their videos best-first.
                      _videoTile(v, best: v.token == videos.firstOrNull?.token)
                  else
                    _lazyHoster(h),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _videoTile(AnimeVideo v, {bool best = false}) => ListTile(
    dense: true,
    leading: Icon(
      best ? Icons.play_circle_fill : Icons.play_circle_outline,
      color: best ? mangaAccent : null,
    ),
    title: Text(v.title.isEmpty ? 'Video' : v.title),
    trailing: v.resolution != null ? Text('${v.resolution}p') : null,
    onTap: () => Navigator.pop(context, v),
  );

  Widget _lazyHoster(AnimeHoster h) {
    final future = _loaded[h.token];
    if (future == null) {
      return ListTile(
        dense: true,
        leading: const Icon(Icons.cloud_download_outlined),
        title: Text(h.lazy ? 'Load videos' : 'Retry loading videos'),
        onTap: () => setState(
          () => _loaded[h.token] = ref
              .read(animeRepositoryProvider)
              .hosterVideos(widget.anime.sourceId, h.token),
        ),
      );
    }
    return FutureBuilder<List<AnimeVideo>>(
      future: future,
      builder: (context, snap) {
        if (snap.hasError) {
          return ListTile(
            dense: true,
            title: Text(
              'Failed: ${snap.error}',
              style: const TextStyle(color: Colors.white54),
            ),
          );
        }
        if (!snap.hasData) {
          return const ListTile(dense: true, title: LinearProgressIndicator());
        }
        if (snap.data!.isEmpty) {
          return const ListTile(
            dense: true,
            title: Text(
              'No videos here.',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }
        return Column(children: [for (final v in snap.data!) _videoTile(v)]);
      },
    );
  }
}
