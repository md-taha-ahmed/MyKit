import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/platform/external_apps.dart';
import '../../domain/entities/stremio_entities.dart';
import '../../movies_routes.dart';
import '../providers/movies_providers.dart';
import '../widgets/movies_widgets.dart';
import 'player_screen.dart';

/// Sources from the stream add-ons (Torrentio) for one movie or episode.
class StreamsScreen extends ConsumerStatefulWidget {
  const StreamsScreen({
    super.key,
    required this.type,
    required this.metaId,
    required this.videoId,
  });

  final String type;
  final String metaId;
  final String videoId;

  @override
  ConsumerState<StreamsScreen> createState() => _StreamsScreenState();
}

class _StreamsScreenState extends ConsumerState<StreamsScreen> {
  static const _order = ['4K', '1080p', '720p', 'SD', 'Other'];
  String? _resolution;

  ({String type, String videoId}) get _key =>
      (type: widget.type, videoId: widget.videoId);

  PlayerArgs _args(MetaDetail? meta, StreamSource source) {
    final episode = meta?.episodes
        .where((e) => e.id == widget.videoId)
        .firstOrNull;
    return PlayerArgs(
      source: source,
      type: widget.type,
      metaId: widget.metaId,
      videoId: widget.videoId,
      name: meta?.name ?? source.filename ?? tr('Video'),
      poster: meta?.preview.poster,
      background: meta?.preview.background,
      episodeLabel: episode == null
          ? null
          : '${episode.code} · ${episode.title}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final meta = ref
        .watch(metaProvider((type: widget.type, id: widget.metaId)))
        .value;
    final streams = ref.watch(streamsProvider(_key));
    final episode = meta?.episodes
        .where((e) => e.id == widget.videoId)
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(meta?.name ?? tr('Sources')),
            if (episode != null)
              Text(
                '${episode.code} · ${episode.title}',
                style: const TextStyle(fontSize: 12.5, color: Colors.white60),
              ),
          ],
        ),
      ),
      body: streams.when(
        loading: () => MessageView(
          icon: Icons.travel_explore,
          title: tr('Looking for sources…'),
          action: SizedBox(width: 160, child: LinearProgressIndicator()),
        ),
        error: (e, _) => MessageView(
          icon: Icons.error_outline,
          title: tr('No sources'),
          message: '$e',
          action: FilledButton(
            onPressed: () => ref.invalidate(streamsProvider(_key)),
            child: Text(tr('Retry')),
          ),
        ),
        data: (all) {
          if (all.isEmpty) {
            return MessageView(
              icon: Icons.search_off,
              title: tr('No sources found'),
              message: tr('Your stream add-ons have nothing for this yet.'),
              action: OutlinedButton(
                onPressed: () => context.push(MoviesRoutes.addons),
                child: Text(tr('Manage add-ons')),
              ),
            );
          }
          final counts = <String, int>{};
          for (final s in all) {
            counts.update(s.resolution, (v) => v + 1, ifAbsent: () => 1);
          }
          final shown = _resolution == null
              ? all
              : all.where((s) => s.resolution == _resolution).toList();
          return Column(
            children: [
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _chip(tr('All ({length})', {'length': all.length}), null),
                    for (final r in _order)
                      if (counts[r] != null)
                        _chip('${tr(r)} (${counts[r]})', r),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  itemCount: shown.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _StreamCard(
                    source: shown[i],
                    onPlay: () => context.push(
                      MoviesRoutes.play,
                      extra: _args(meta, shown[i]),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _chip(String label, String? value) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: _resolution == value,
      selectedColor: moviesAccent.withValues(alpha: 0.35),
      onSelected: (_) => setState(() => _resolution = value),
    ),
  );
}

class _StreamCard extends StatelessWidget {
  const _StreamCard({required this.source, required this.onPlay});

  final StreamSource source;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final seeders = source.seeders;
    final stats = [
      if (seeders != null) '👤 $seeders',
      if (source.size != null) '💾 ${source.size}',
      if (source.provider != null) source.provider!,
    ];
    return Material(
      color: const Color(0xFF1C1C24),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPlay,
        onLongPress: () => _showActions(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 64,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: moviesAccent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  source.quality,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.release,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [
                        ...stats,
                        if (!source.isTorrent) tr('Direct link'),
                      ].join('   '),
                      style: TextStyle(
                        fontSize: 12,
                        color: seeders != null && seeders < 5
                            ? Colors.orangeAccent
                            : Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: tr('More'),
                icon: const Icon(Icons.more_vert, size: 20),
                onPressed: () => _showActions(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showActions(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: Text(tr('Play')),
              onTap: () => Navigator.pop(context, 'play'),
            ),
            if (source.url != null)
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: Text(tr('Open in another player')),
                onTap: () => Navigator.pop(context, 'external'),
              ),
            if (source.isTorrent)
              ListTile(
                leading: const Icon(Icons.link),
                title: Text(tr('Copy magnet link')),
                onTap: () => Navigator.pop(context, 'magnet'),
              ),
          ],
        ),
      ),
    );
    switch (action) {
      case 'play':
        onPlay();
      case 'external':
        final ok = await ExternalApps.openVideo(source.url!);
        if (!ok) {
          messenger.showSnackBar(
            SnackBar(content: Text(tr('No video player app found.'))),
          );
        }
      case 'magnet':
        final trackers = source.trackers
            .map((t) => '&tr=${Uri.encodeComponent(t)}')
            .join();
        await Clipboard.setData(
          ClipboardData(
            text: 'magnet:?xt=urn:btih:${source.infoHash}$trackers',
          ),
        );
        messenger.showSnackBar(
          SnackBar(content: Text(tr('Magnet link copied'))),
        );
    }
  }
}
