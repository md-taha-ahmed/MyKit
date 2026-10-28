import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/platform/external_apps.dart';
import '../../domain/entities/feed_article.dart';
import '../../rss_routes.dart';
import '../providers/rss_providers.dart';
import '../widgets/article_actions.dart';
import '../widgets/article_tile.dart';

const _likeColor = Color(0xFFFF5A6E);
const _cardColor = Color(0xFF17171A);

/// Full-screen, swipe-up feed of article briefs (one per screen).
/// Half photo, half article, shuffled (YouTube videos mixed in). Double-tap to like; action bar to like,
/// bookmark, delete or read the full article.
class RssScrollScreen extends ConsumerStatefulWidget {
  const RssScrollScreen({super.key, this.categoryId, this.feedId});

  /// Same values as the home chips (null = all, or saved/liked filters).
  final String? categoryId;

  /// Show a single feed instead of a category.
  final String? feedId;

  @override
  ConsumerState<RssScrollScreen> createState() => _RssScrollScreenState();
}

class _RssScrollScreenState extends ConsumerState<RssScrollScreen> {
  final _pager = PageController();

  /// Snapshot of the list so deleting doesn't make pages jump under the finger.
  List<FeedArticle>? _articles;

  ArticleFilter get _filter =>
      (categoryId: widget.categoryId, feedId: widget.feedId);

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void _onPage(int i) {
    final articles = _articles;
    if (articles == null || i >= articles.length) return;
    ref.read(rssReadIdsProvider.notifier).markRead([articles[i].id]);
  }

  /// Random mix of everything (so videos and articles interleave instead of
  /// sorting by date), unread first.
  List<FeedArticle> _mixed(List<FeedArticle> articles) {
    final read = ref.read(rssReadIdsProvider);
    final rnd = Random();
    final unread = articles.where((a) => !read.contains(a.id)).toList()
      ..shuffle(rnd);
    final seen = articles.where((a) => read.contains(a.id)).toList()
      ..shuffle(rnd);
    return [...unread, ...seen];
  }

  Future<void> _delete(FeedArticle article) async {
    final fromSaved = widget.categoryId == savedArticlesFilter;
    await deleteArticle(context, ref, article, fromSaved: fromSaved);
    if (!mounted) return;
    setState(() => _articles = [..._articles!]..remove(article));
  }

  @override
  Widget build(BuildContext context) {
    // Take the snapshot once; new articles from a refresh don't reshuffle pages.
    _articles ??= _mixed(ref.read(filteredArticlesProvider(_filter)));
    final articles = _articles!;
    final library = ref.watch(rssLibraryProvider);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _cardColor,
        appBar: articles.isEmpty ? AppBar(title: const Text('Brief')) : null,
        body: articles.isEmpty
            ? const Center(
                child: Text(
                  'Nothing to show here.',
                  style: TextStyle(color: Colors.white60),
                ),
              )
            : PageView.builder(
                controller: _pager,
                scrollDirection: Axis.vertical,
                itemCount: articles.length,
                onPageChanged: _onPage,
                itemBuilder: (context, i) {
                  if (i == 0) {
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _onPage(0),
                    );
                  }
                  final article = articles[i];
                  return _BriefPage(
                    article: article,
                    feedTitle: library.feedById(article.feedId)?.title ?? '',
                    isVideo:
                        library.feedById(article.feedId)?.isYoutube ?? false,
                    position: '${i + 1} / ${articles.length}',
                    onDelete: () => _delete(article),
                  );
                },
              ),
      ),
    );
  }
}

class _BriefPage extends ConsumerStatefulWidget {
  const _BriefPage({
    required this.article,
    required this.feedTitle,
    required this.position,
    required this.onDelete,
    this.isVideo = false,
  });

  final FeedArticle article;
  final String feedTitle;
  final String position;
  final VoidCallback onDelete;
  final bool isVideo;

  @override
  ConsumerState<_BriefPage> createState() => _BriefPageState();
}

class _BriefPageState extends ConsumerState<_BriefPage>
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

  /// Opens the video in ReVanced / YouTube (see [ExternalApps.openYoutube]).
  Future<void> _watch(String? link) async {
    if (link == null) return;
    ref.read(rssReadIdsProvider.notifier).markRead([widget.article.id]);
    await ExternalApps.openYoutube(link);
  }

  void _doubleTapLike() {
    ref.read(rssReactionsProvider.notifier).like(widget.article.id);
    HapticFeedback.lightImpact();
    _heart.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.article;
    final accent = Theme.of(context).colorScheme.primary;
    final reactions = ref.watch(rssReactionsProvider);
    final liked = reactions.isLiked(a.id);
    final saved = reactions.isSaved(a.id);
    final brief = a.summary.isNotEmpty ? a.summary : a.content;

    return GestureDetector(
      onDoubleTap: _doubleTapLike,
      child: Column(
        children: [
          // --- Photo: takes all the space the card doesn't need ----------
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _Photo(url: a.imageUrl),
                if (widget.isVideo)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Material(
                        color: const Color(0xCCFF3B30),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => _watch(a.link),
                          child: const Padding(
                            padding: EdgeInsets.all(14),
                            child: Icon(
                              Icons.play_arrow,
                              size: 40,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                // Back button + position, over the photo.
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _GlassButton(
                          icon: Icons.arrow_back,
                          onTap: () => Navigator.of(context).maybePop(),
                        ),
                        const Spacer(),
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: _Pill(text: widget.position),
                        ),
                      ],
                    ),
                  ),
                ),
                // Double-tap heart burst.
                IgnorePointer(
                  child: Center(child: _HeartBurst(animation: _heart)),
                ),
              ],
            ),
          ),
          // --- Article card: sized to its content -----------------------
          Transform.translate(
            // Overlap the photo slightly for a card-on-photo look.
            offset: const Offset(0, -20),
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: _cardColor,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SourceRow(
                      name: widget.feedTitle,
                      time: relativeTime(a.publishedAt),
                      accent: accent,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      a.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    if (brief.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      // Capped so a long summary never squeezes the photo.
                      Text(
                        brief,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.5,
                          color: Color(0xFFB8B8C0),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    const Divider(height: 1, color: Colors.white12),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          _ActionButton(
                            icon: liked
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: liked ? _likeColor : Colors.white70,
                            tooltip: liked ? 'Unlike' : 'Like',
                            onTap: () => ref
                                .read(rssReactionsProvider.notifier)
                                .toggleLike(a.id),
                          ),
                          _ActionButton(
                            icon: saved
                                ? Icons.bookmark
                                : Icons.bookmark_border,
                            color: saved ? accent : Colors.white70,
                            tooltip: saved ? 'Remove bookmark' : 'Save',
                            onTap: () => toggleSaveArticle(context, ref, a),
                          ),
                          _ActionButton(
                            icon: Icons.delete_outline,
                            color: Colors.white70,
                            tooltip: 'Delete',
                            onTap: widget.onDelete,
                          ),
                          const Spacer(),
                          if (widget.isVideo)
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFFF3B30),
                              ),
                              onPressed: () => _watch(a.link),
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Watch'),
                            )
                          else
                            FilledButton.icon(
                              onPressed: () =>
                                  context.push(RssRoutes.article(a.id)),
                              icon: const Icon(
                                Icons.chrome_reader_mode_outlined,
                              ),
                              label: const Text('Read'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Whole photo (never cropped), centred over a blurred copy of itself.
class _Photo extends StatelessWidget {
  const _Photo({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null) return const _Gradient();
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Image.network(
            url!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const _Gradient(),
          ),
        ),
        const ColoredBox(color: Color(0x73000000)),
        // The photo as a rounded, shadowed card centred on the blurred
        // backdrop (below the top buttons, above the overlapping card).
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 60, 16, 40),
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x99000000),
                      blurRadius: 30,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.network(
                    url!,
                    width: double.infinity,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.name,
    required this.time,
    required this.accent,
  });

  final String name;
  final String time;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 13,
          backgroundColor: accent.withValues(alpha: .2),
          child: Text(
            name.isEmpty ? '?' : name.characters.first.toUpperCase(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        if (time.isNotEmpty)
          Text(
            time,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onTap,
    icon: Icon(icon, color: color, size: 26),
  );
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0x66000000),
    shape: const CircleBorder(),
    child: IconButton(
      icon: Icon(icon, color: Colors.white),
      onPressed: onTap,
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0x66000000),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: const TextStyle(color: Colors.white, fontSize: 12.5),
    ),
  );
}

class _HeartBurst extends StatelessWidget {
  const _HeartBurst({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    builder: (context, _) {
      final t = animation.value;
      if (t == 0 || t == 1) return const SizedBox.shrink();
      final scale = Curves.elasticOut.transform((t * 1.6).clamp(0, 1));
      final opacity = t < .6 ? 1.0 : (1 - (t - .6) / .4);
      return Opacity(
        opacity: opacity.clamp(0, 1),
        child: Transform.scale(
          scale: .4 + scale * .8,
          child: const Icon(
            Icons.favorite,
            size: 110,
            color: _likeColor,
            shadows: [Shadow(blurRadius: 24, color: Colors.black54)],
          ),
        ),
      );
    },
  );
}

class _Gradient extends StatelessWidget {
  const _Gradient();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF2B3A55), Color(0xFF151A24)],
      ),
    ),
  );
}
