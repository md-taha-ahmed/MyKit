import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/i18n/i18n.dart';
import '../../domain/entities/stremio_entities.dart';
import '../../movies_routes.dart';
import '../providers/movies_providers.dart';
import '../widgets/movies_widgets.dart';

/// Backdrop, poster, info and — for series — seasons and episodes.
class TitleDetailsScreen extends ConsumerStatefulWidget {
  const TitleDetailsScreen({super.key, required this.type, required this.id});

  final String type;
  final String id;

  @override
  ConsumerState<TitleDetailsScreen> createState() => _TitleDetailsScreenState();
}

class _TitleDetailsScreenState extends ConsumerState<TitleDetailsScreen> {
  int? _season;

  @override
  Widget build(BuildContext context) {
    final meta = ref.watch(metaProvider((type: widget.type, id: widget.id)));
    return Scaffold(
      body: meta.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Scaffold(
          appBar: AppBar(),
          body: MessageView(
            icon: Icons.error_outline,
            title: tr('Could not load this title'),
            message: '$e',
            action: FilledButton(
              onPressed: () => ref.invalidate(
                metaProvider((type: widget.type, id: widget.id)),
              ),
              child: Text(tr('Retry')),
            ),
          ),
        ),
        data: _content,
      ),
    );
  }

  Widget _content(MetaDetail meta) {
    final isSeries = meta.type == MediaType.series.id;
    final history = ref.watch(watchHistoryProvider);
    final seasons = meta.seasons;
    final lastWatched = history.where((e) => e.metaId == meta.id).firstOrNull;
    var season = _season ?? seasons.firstOrNull;
    if (_season == null && lastWatched != null && isSeries) {
      season =
          meta.episodes
              .where((e) => e.id == lastWatched.videoId)
              .firstOrNull
              ?.season ??
          season;
    }
    final episodes = meta.episodes.where((e) => e.season == season).toList();

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 230,
          // Stays readable over bright backdrops.
          leading: Padding(
            padding: const EdgeInsets.all(8),
            child: IconButton.filled(
              style: IconButton.styleFrom(
                backgroundColor: Colors.black45,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(
              fit: StackFit.expand,
              children: [
                NetImage(meta.preview.background ?? meta.preview.poster),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black26,
                        Colors.transparent,
                        Colors.black,
                      ],
                      stops: [0, 0.45, 1],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(child: _header(meta, lastWatched)),
        if (isSeries && seasons.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final s in seasons)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(
                          s == 0 ? tr('Specials') : tr('Season {s}', {'s': s}),
                        ),
                        selected: s == season,
                        selectedColor: moviesAccent.withValues(alpha: 0.35),
                        onSelected: (_) => setState(() => _season = s),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverList.builder(
            itemCount: episodes.length,
            itemBuilder: (_, i) =>
                _EpisodeTile(meta: meta, episode: episodes[i]),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  Widget _header(MetaDetail meta, WatchEntry? lastWatched) {
    final isSeries = meta.type == MediaType.series.id;
    final facts = [
      if (meta.preview.releaseInfo != null) meta.preview.releaseInfo!,
      if (meta.runtime != null) meta.runtime!,
      if (meta.preview.imdbRating?.isNotEmpty ?? false)
        '★ ${meta.preview.imdbRating}',
    ];
    final resume = lastWatched != null && !lastWatched.finished;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 96,
                  height: 144,
                  child: NetImage(meta.preview.poster),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meta.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      facts.join('  ·  '),
                      style: const TextStyle(color: Colors.white70),
                    ),
                    if (meta.genres.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        meta.genres.take(4).join(', '),
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!isSeries || resume)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: moviesAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.play_arrow),
                label: Text(
                  resume
                      ? (lastWatched.episodeLabel != null
                            ? tr('Resume {episode}', {
                                'episode': lastWatched.episodeLabel!
                                    .split(' ·')
                                    .first,
                              })
                            : tr('Resume'))
                      : tr('Watch'),
                ),
                onPressed: () => context.push(
                  MoviesRoutes.streams(
                    meta.type,
                    meta.id,
                    resume ? lastWatched.videoId : meta.id,
                  ),
                ),
              ),
            ),
          if (meta.description != null) ...[
            const SizedBox(height: 14),
            _ExpandableText(meta.description!),
          ],
          if (meta.director.isNotEmpty || meta.cast.isNotEmpty) ...[
            const SizedBox(height: 10),
            if (meta.director.isNotEmpty)
              _Credit(tr('Director'), meta.director.join(', ')),
            if (meta.cast.isNotEmpty)
              _Credit(tr('Cast'), meta.cast.take(6).join(', ')),
          ],
        ],
      ),
    );
  }
}

class _Credit extends StatelessWidget {
  const _Credit(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label  ',
            style: const TextStyle(color: Colors.white54),
          ),
          TextSpan(text: value),
        ],
      ),
      style: const TextStyle(fontSize: 13),
    ),
  );
}

class _ExpandableText extends StatefulWidget {
  const _ExpandableText(this.text);

  final String text;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _open = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => setState(() => _open = !_open),
    child: Text(
      widget.text,
      maxLines: _open ? null : 4,
      overflow: _open ? null : TextOverflow.ellipsis,
      style: const TextStyle(color: Colors.white70, height: 1.4),
    ),
  );
}

class _EpisodeTile extends ConsumerWidget {
  const _EpisodeTile({required this.meta, required this.episode});

  final MetaDetail meta;
  final Episode episode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watched = ref
        .watch(watchHistoryProvider)
        .where((e) => e.videoId == episode.id)
        .firstOrNull;
    final upcoming = episode.isUpcoming;
    final date = episode.released == null
        ? null
        : DateFormat.yMMMd().format(episode.released!.toLocal());

    return InkWell(
      onTap: upcoming
          ? null
          : () => context.push(
              MoviesRoutes.streams(meta.type, meta.id, episode.id),
            ),
      child: Opacity(
        opacity: upcoming ? 0.5 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 128,
                  height: 72,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      NetImage(episode.thumbnail, icon: Icons.tv),
                      if (watched != null)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: WatchProgressBar(
                            watched.finished ? 1 : watched.fraction,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${episode.number}. ${episode.title}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    if (date != null)
                      Text(
                        upcoming ? tr('Airs {date}', {'date': date}) : date,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white54,
                        ),
                      ),
                    if (episode.overview != null)
                      Text(
                        episode.overview!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white60,
                        ),
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
