import 'dart:async';

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

/// One of the two reusable players: plays the current Short or preloads
/// the next. Reusing them (instead of a player per Short) keeps memory and
/// hardware video decoders in check, and makes swiping instant.
class _Slot {
  _Slot() {
    final native = player.platform;
    if (native is NativePlayer) {
      // Read well ahead in memory (Shorts are short), so a slow moment on
      // the network doesn't stall playback.
      native.setProperty('demuxer-readahead-secs', '20');
      native.setProperty('demuxer-max-bytes', '${48 * 1024 * 1024}');
    }
    player.setPlaylistMode(PlaylistMode.single); // loop
  }

  final player = Player(
    configuration: const PlayerConfiguration(bufferSize: 32 * 1024 * 1024),
  );

  /// Fixed-size surface created up front, so the decoder has somewhere to
  /// draw from the first frame (otherwise mpv starts with no surface and
  /// has to restart the decoder when the page appears — a ~2 s stall).
  late final controller = VideoController(
    player,
    configuration: const VideoControllerConfiguration(width: 720, height: 1280),
  );

  /// The page (index) loaded into this player, if any.
  int? page;
  bool ready = false;

  /// Bumped on every load, so a slow, outdated load can't take over.
  int token = 0;
}

/// Full-screen, swipe-up Shorts player. Falls back to a single-file stream,
/// then to the YouTube app, when a Short won't play here.
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
  final _pager = PageController();
  final _slots = [_Slot(), _Slot()];
  final _subs = <StreamSubscription<Object?>>[];

  int _current = 0;
  bool _muted = false;
  bool _pausedByUser = false;
  Timer? _watchdog;

  /// Pages already switched to their single-file stream / given up on.
  final _onFallback = <int>{};
  final _failed = <int>{};

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
    for (final slot in _slots) {
      _subs.add(
        slot.player.stream.error.listen((e) {
          debugPrint('Shorts: player error on page ${slot.page}: $e');
          final page = slot.page;
          if (page != null) _fallBack(page, slot, 'player error: $e');
        }),
      );
    }
    if (_shorts.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _activate(0));
    }
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _watchdog?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    for (final slot in _slots) {
      slot.player.dispose();
    }
    _pager.dispose();
    super.dispose();
  }

  _Slot? _slotFor(int page) {
    for (final s in _slots) {
      if (s.page == page) return s;
    }
    return null;
  }

  /// Page [i] is now on screen: play it, preload the next one.
  void _activate(int i) {
    if (!mounted || i >= _shorts.length) return;
    _watchdog?.cancel();
    setState(() {
      _current = i;
      _pausedByUser = false;
    });
    ref.read(rssReadIdsProvider.notifier).markRead([_shorts[i].id]);

    var slot = _slotFor(i);
    for (final s in _slots) {
      if (s != slot) s.player.pause();
    }
    if (slot == null) {
      // Not preloaded (first one, or swiping back): use the player that
      // doesn't hold the next page.
      slot = _slots.firstWhere((s) => s.page != i + 1);
      _load(i, slot);
    } else if (slot.ready) {
      _start(slot, fromStart: true);
    }

    // The next one is preloaded once this one is actually playing (see
    // [_start]), so they don't compete for the connection at the start.
    if (slot.ready) _preloadAfter(i);
    // Resolve one more ahead (just the URLs; cheap).
    final later = i + 2;
    if (later < _shorts.length) {
      final id = _shorts[later].youtubeId;
      if (id != null) ref.read(shortsNativeProvider).prefetch(id);
    }
  }

  void _preloadAfter(int i) {
    final next = i + 1;
    if (next >= _shorts.length || _slotFor(next) != null) return;
    final current = _slotFor(i);
    _load(next, _slots.firstWhere((s) => s != current));
  }

  Future<void> _load(int page, _Slot slot, {bool fallback = false}) async {
    if (_disposed) return;
    final token = ++slot.token;
    slot
      ..page = page
      ..ready = false;
    await slot.player.stop();
    if (mounted) setState(() {});
    final id = _shorts[page].youtubeId;
    try {
      if (id == null) throw StateError('No video id');
      final stream = await ref.read(shortsNativeProvider).resolve(id);
      if (token != slot.token) return;
      final single = fallback ? stream.fallback : null;
      if (fallback && single == null) throw StateError('No fallback stream');
      await slot.player.setVolume(_muted ? 0 : 100);
      await slot.player.open(Media(single ?? stream.video), play: false);
      // Wait until the video is open; only then add the separate audio
      // (adding it earlier fails and leaves the Short stuck).
      if (slot.player.state.duration == Duration.zero) {
        await slot.player.stream.duration
            .firstWhere((d) => d > Duration.zero)
            .timeout(const Duration(seconds: 8));
      }
      if (token != slot.token || _disposed) return;
      if (single == null && stream.audio != null) {
        await slot.player.setAudioTrack(AudioTrack.uri(stream.audio!));
      }
      if (token != slot.token) return;
      slot.ready = true;
      if (mounted) setState(() {});
      if (page == _current && !_pausedByUser) _start(slot);
    } catch (e) {
      if (token != slot.token || _disposed) return;
      debugPrint('Shorts: load failed on page $page (fallback=$fallback): $e');
      await _fallBack(page, slot, '$e');
    }
  }

  /// HD pair failed → try the single-file stream once; then give up (the
  /// page offers "Watch in YouTube").
  Future<void> _fallBack(int page, _Slot slot, String why) async {
    if (slot.page != page) return;
    if (!_onFallback.contains(page)) {
      _onFallback.add(page);
      debugPrint('Shorts: page $page → single-file stream ($why)');
      await _load(page, slot, fallback: true);
      return;
    }
    _failed.add(page);
    slot.ready = false;
    if (mounted) setState(() {});
  }

  /// Plays (from the beginning for a Short that was preloaded); if the
  /// position hasn't moved after a moment, nudges it, and as a last resort
  /// switches to the single-file stream.
  Future<void> _start(_Slot slot, {bool fromStart = false}) async {
    final page = slot.page;
    if (page == null) return;
    _watchdog?.cancel();
    if (fromStart) await slot.player.seek(Duration.zero);
    await slot.player.play();
    final from = slot.player.state.position;
    var checks = 0;
    _watchdog = Timer.periodic(const Duration(milliseconds: 1200), (t) async {
      if (!mounted || slot.page != page || page != _current || _pausedByUser) {
        return t.cancel();
      }
      final state = slot.player.state;
      if (state.position != from && state.playing) {
        t.cancel();
        _preloadAfter(page);
        return;
      }
      checks++;
      if (state.buffering && checks < 6) return; // still loading
      if (checks <= 3) {
        await slot.player.pause();
        await slot.player.seek(state.position);
        await slot.player.play();
        return;
      }
      t.cancel();
      _fallBack(page, slot, 'stuck at ${state.position}');
    });
  }

  void _togglePause() {
    final slot = _slotFor(_current);
    if (slot == null || !slot.ready) return;
    setState(() => _pausedByUser = !_pausedByUser);
    if (_pausedByUser) {
      _watchdog?.cancel();
      slot.player.pause();
    } else {
      _start(slot);
    }
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    for (final s in _slots) {
      s.player.setVolume(_muted ? 0 : 100);
    }
  }

  Future<void> _openInYoutube(FeedArticle short) async {
    final link = short.link;
    if (link == null) return;
    for (final s in _slots) {
      await s.player.pause();
    }
    await ExternalApps.openYoutube(link);
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
                // Keep the next page laid out, so its video surface is
                // ready before you swipe to it.
                allowImplicitScrolling: true,
                itemCount: _shorts.length,
                onPageChanged: _activate,
                itemBuilder: (context, i) {
                  final slot = _slotFor(i);
                  return _ShortPage(
                    key: ValueKey(_shorts[i].id),
                    short: _shorts[i],
                    slot: slot,
                    ready: slot != null && slot.ready,
                    failed: _failed.contains(i),
                    paused: i == _current && _pausedByUser,
                    muted: _muted,
                    onTap: _togglePause,
                    onToggleMute: _toggleMute,
                    onOpenInYoutube: () => _openInYoutube(_shorts[i]),
                  );
                },
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
    required this.slot,
    required this.ready,
    required this.failed,
    required this.paused,
    required this.muted,
    required this.onTap,
    required this.onToggleMute,
    required this.onOpenInYoutube,
  });

  final FeedArticle short;

  /// The player assigned to this Short (loading or ready).
  final _Slot? slot;

  /// Its video is loaded; until then the thumbnail covers the player.
  final bool ready;
  final bool failed;
  final bool paused;
  final bool muted;
  final VoidCallback onTap;
  final VoidCallback onToggleMute;
  final VoidCallback onOpenInYoutube;

  @override
  ConsumerState<_ShortPage> createState() => _ShortPageState();
}

class _ShortPageState extends ConsumerState<_ShortPage>
    with SingleTickerProviderStateMixin {
  late final _heart = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void dispose() {
    _heart.dispose();
    super.dispose();
  }

  void _like() {
    ref.read(rssReactionsProvider.notifier).like(widget.short.id);
    HapticFeedback.lightImpact();
    _heart.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.short;
    final slot = widget.slot;
    final reactions = ref.watch(rssReactionsProvider);
    final liked = reactions.isLiked(s.id);
    final saved = reactions.isSaved(s.id);
    final channel =
        ref.watch(rssLibraryProvider).feedById(s.feedId)?.title ?? '';

    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTap: _like,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The player's surface is in place from the start; the thumbnail
          // covers it until the video is loaded.
          if (slot != null)
            Video(
              controller: slot.controller,
              fit: BoxFit.cover,
              controls: NoVideoControls,
            ),
          if (!widget.ready && s.imageUrl != null)
            Image.network(
              s.imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          if (!widget.ready && !widget.failed)
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          if (widget.failed)
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
                    onPressed: widget.onOpenInYoutube,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Watch in YouTube'),
                  ),
                ],
              ),
            ),
          if (widget.paused)
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
                    onTap: widget.onOpenInYoutube,
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
          if (slot != null && widget.ready)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: StreamBuilder<Duration>(
                stream: slot.player.stream.position,
                builder: (context, snap) {
                  final total = slot.player.state.duration.inMilliseconds;
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
