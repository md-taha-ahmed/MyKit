import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../../core/platform/external_apps.dart';
import '../../../../core/utils/text_direction.dart';
import '../../data/datasources/shorts_native_data_source.dart';
import '../../domain/entities/feed_article.dart';
import '../providers/rss_providers.dart';
import '../widgets/article_actions.dart';

final shortsNativeProvider = Provider<ShortsNativeDataSource>(
  (ref) => ShortsNativeDataSource(),
);

/// YouTube Shorts from the selected feeds, newest first and unseen first.
final shortsProvider = Provider.family<List<FeedArticle>, ArticleFilter>((
  ref,
  filter,
) {
  final read = ref.watch(rssReadIdsProvider);
  final shorts = ref
      .watch(filteredArticlesProvider(filter))
      .where((a) => a.isShort)
      .toList();
  return [
    ...shorts.where((a) => !read.contains(a.id)),
    ...shorts.where((a) => read.contains(a.id)),
  ];
});

/// Full-screen, swipe-up Shorts player (plays in MyKit; falls back to the
/// YouTube app when a Short can't be loaded here).
class ShortsScreen extends ConsumerStatefulWidget {
  const ShortsScreen({super.key, this.startId, this.categoryId, this.feedId});

  /// Article id of the Short to start with.
  final String? startId;
  final String? categoryId;
  final String? feedId;

  @override
  ConsumerState<ShortsScreen> createState() => _ShortsScreenState();
}

class _ShortsScreenState extends ConsumerState<ShortsScreen> {
  late final List<FeedArticle> _shorts;
  late final PageController _pager;
  int _current = 0;
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    final all = ref.read(
      shortsProvider((categoryId: widget.categoryId, feedId: widget.feedId)),
    );
    // Start with the tapped Short, then the rest in order.
    final start = all.indexWhere((a) => a.id == widget.startId);
    _shorts = start <= 0
        ? all
        : [all[start], ...all.sublist(0, start), ...all.sublist(start + 1)];
    _pager = PageController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _onPage(0));
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void _onPage(int i) {
    if (i >= _shorts.length) return;
    setState(() => _current = i);
    ref.read(rssReadIdsProvider.notifier).markRead([_shorts[i].id]);
    // Fetch the next two ahead so swiping is instant.
    final native = ref.read(shortsNativeProvider);
    for (final next in _shorts.skip(i + 1).take(2)) {
      final id = next.youtubeId;
      if (id != null) native.prefetch(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _shorts.isEmpty
            ? const _NoShorts()
            : PageView.builder(
                controller: _pager,
                scrollDirection: Axis.vertical,
                itemCount: _shorts.length,
                onPageChanged: _onPage,
                itemBuilder: (context, i) => _ShortPage(
                  key: ValueKey(_shorts[i].id),
                  short: _shorts[i],
                  active: i == _current,
                  muted: _muted,
                  onToggleMute: () => setState(() => _muted = !_muted),
                ),
              ),
      ),
    );
  }
}

class _NoShorts extends StatelessWidget {
  const _NoShorts();

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        const Expanded(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'No Shorts here yet. Shorts from your YouTube channels show '
                'up after a refresh.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _ShortPage extends ConsumerStatefulWidget {
  const _ShortPage({
    super.key,
    required this.short,
    required this.active,
    required this.muted,
    required this.onToggleMute,
  });

  final FeedArticle short;
  final bool active;
  final bool muted;
  final VoidCallback onToggleMute;

  @override
  ConsumerState<_ShortPage> createState() => _ShortPageState();
}

class _ShortPageState extends ConsumerState<_ShortPage>
    with SingleTickerProviderStateMixin {
  late final Player _player = Player(
    configuration: const PlayerConfiguration(bufferSize: 16 * 1024 * 1024),
  );
  late final VideoController _video = VideoController(_player);
  late final _heart = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  bool _loading = true;
  bool _failed = false;
  bool _pausedByUser = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.short.youtubeId;
    if (id == null) return setState(() => _failed = true);
    try {
      final stream = await ref.read(shortsNativeProvider).resolve(id);
      if (!mounted) return;
      await _player.setPlaylistMode(PlaylistMode.single); // loop
      await _player.setVolume(widget.muted ? 0 : 100);
      await _player.open(Media(stream.video), play: false);
      if (stream.audio != null) {
        await _player.setAudioTrack(AudioTrack.uri(stream.audio!));
      }
      if (!mounted) return;
      setState(() => _loading = false);
      if (widget.active) await _player.play();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  void didUpdateWidget(_ShortPage old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active && !_loading && !_failed) {
      if (widget.active) {
        _pausedByUser = false;
        _player.play();
      } else {
        _player.pause();
        _player.seek(Duration.zero);
      }
    }
    if (old.muted != widget.muted) _player.setVolume(widget.muted ? 0 : 100);
  }

  @override
  void dispose() {
    _heart.dispose();
    _player.dispose();
    super.dispose();
  }

  void _togglePause() {
    if (_loading || _failed) return;
    setState(() => _pausedByUser = !_pausedByUser);
    _pausedByUser ? _player.pause() : _player.play();
  }

  void _like() {
    ref.read(rssReactionsProvider.notifier).like(widget.short.id);
    HapticFeedback.lightImpact();
    _heart.forward(from: 0);
  }

  Future<void> _openInYoutube() async {
    final link = widget.short.link;
    if (link == null) return;
    await _player.pause();
    await ExternalApps.openYoutube(link);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.short;
    final reactions = ref.watch(rssReactionsProvider);
    final liked = reactions.isLiked(s.id);
    final saved = reactions.isSaved(s.id);
    final channel =
        ref.watch(rssLibraryProvider).feedById(s.feedId)?.title ?? '';

    return GestureDetector(
      onTap: _togglePause,
      onDoubleTap: _like,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Thumbnail until the video starts.
          if (s.imageUrl != null)
            Image.network(
              s.imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          if (!_loading && !_failed)
            Video(
              controller: _video,
              fit: BoxFit.cover,
              controls: NoVideoControls,
            ),
          if (_loading)
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          if (_failed)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Can\'t play this one here.',
                    style: TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFF3B30),
                    ),
                    onPressed: _openInYoutube,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Watch in YouTube'),
                  ),
                ],
              ),
            ),
          if (_pausedByUser)
            const Center(
              child: Icon(
                Icons.play_arrow_rounded,
                size: 84,
                color: Colors.white70,
              ),
            ),
          IgnorePointer(
            child: Center(
              child: ScaleTransition(
                scale: CurvedAnimation(
                  parent: _heart,
                  curve: Curves.elasticOut,
                ),
                child: FadeTransition(
                  opacity: ReverseAnimation(_heart),
                  child: const Icon(
                    Icons.favorite,
                    size: 110,
                    color: Color(0xFFFF5A6E),
                  ),
                ),
              ),
            ),
          ),
          // Bottom: shade, channel and title.
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xCC000000)],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 84,
            bottom: 28,
            child: SafeArea(
              top: false,
              child: AutoDirection(
                text: s.title,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      channel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      s.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Right: actions.
          Positioned(
            right: 8,
            bottom: 24,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SideButton(
                    icon: liked ? Icons.favorite : Icons.favorite_border,
                    color: liked ? const Color(0xFFFF5A6E) : Colors.white,
                    label: 'Like',
                    onTap: () => ref
                        .read(rssReactionsProvider.notifier)
                        .toggleLike(s.id),
                  ),
                  _SideButton(
                    icon: saved ? Icons.bookmark : Icons.bookmark_border,
                    label: 'Save',
                    onTap: () => toggleSaveArticle(context, ref, s),
                  ),
                  _SideButton(
                    icon: widget.muted ? Icons.volume_off : Icons.volume_up,
                    label: widget.muted ? 'Muted' : 'Sound',
                    onTap: widget.onToggleMute,
                  ),
                  _SideButton(
                    icon: Icons.open_in_new,
                    label: 'YouTube',
                    onTap: _openInYoutube,
                  ),
                ],
              ),
            ),
          ),
          // Top: back.
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ),
          // Progress along the bottom edge.
          if (!_loading && !_failed)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: StreamBuilder<Duration>(
                stream: _player.stream.position,
                builder: (context, snap) {
                  final total = _player.state.duration.inMilliseconds;
                  final pos = snap.data?.inMilliseconds ?? 0;
                  return LinearProgressIndicator(
                    value: total == 0 ? 0 : (pos / total).clamp(0, 1),
                    minHeight: 2,
                    color: Colors.white,
                    backgroundColor: Colors.white24,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _SideButton extends StatelessWidget {
  const _SideButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: InkResponse(
      onTap: onTap,
      radius: 28,
      child: Column(
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 11.5),
          ),
        ],
      ),
    ),
  );
}
