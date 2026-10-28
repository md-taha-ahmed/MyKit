import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/manga_entities.dart';
import '../../manga_routes.dart';
import '../providers/manga_providers.dart';
import '../widgets/manga_widgets.dart';

/// Chapter reader: right-to-left / left-to-right pages or vertical strip.
class MangaReaderScreen extends ConsumerStatefulWidget {
  const MangaReaderScreen({
    super.key,
    required this.mangaKey,
    required this.chapterUrl,
  });

  final String mangaKey;
  final String chapterUrl;

  @override
  ConsumerState<MangaReaderScreen> createState() => _MangaReaderScreenState();
}

class _MangaReaderScreenState extends ConsumerState<MangaReaderScreen> {
  PageController? _pager;
  final _strip = ScrollController();
  int _page = 0;
  bool _ui = false;
  bool _restored = false;

  ChapterRef get _ref =>
      (mangaKey: widget.mangaKey, chapterUrl: widget.chapterUrl);

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    final progress = ref
        .read(mangaLibraryProvider.notifier)
        .progressFor(widget.mangaKey);
    if (progress?.lastChapterUrl == widget.chapterUrl) {
      _page = progress!.lastPage;
    }
    _strip.addListener(_onStripScroll);
  }

  @override
  void dispose() {
    _pager?.dispose();
    _strip.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Manga get _manga => ref.read(mangaCacheProvider)[widget.mangaKey]!;

  void _onPage(int page, int total) {
    if (page == _page && _restored) return;
    setState(() => _page = page);
    ref
        .read(mangaLibraryProvider.notifier)
        .saveProgress(
          _manga,
          widget.chapterUrl,
          page,
          finished: page >= total - 1,
        );
    _prefetch(page, total);
  }

  /// Downloads the next pages ahead of time.
  void _prefetch(int page, int total) {
    final pages = ref.read(chapterPagesProvider(_ref)).value;
    if (pages == null) return;
    for (var i = page + 1; i <= page + 3 && i < total; i++) {
      ref.read(pageImageProvider((sourceId: _manga.sourceId, page: pages[i])));
    }
  }

  void _onStripScroll() {
    final pages = ref.read(chapterPagesProvider(_ref)).value;
    if (pages == null || !_strip.hasClients) return;
    final max = _strip.position.maxScrollExtent;
    if (max <= 0) return;
    final page = ((_strip.offset / max) * (pages.length - 1)).round();
    _onPage(page.clamp(0, pages.length - 1), pages.length);
  }

  /// Neighbouring chapter in reading order (chapters are newest-first).
  Chapter? _neighbour(int delta) {
    final chapters = ref.read(chaptersProvider(widget.mangaKey)).value;
    if (chapters == null) return null;
    final i = chapters.indexWhere((c) => c.url == widget.chapterUrl);
    final j = i - delta;
    return i < 0 || j < 0 || j >= chapters.length ? null : chapters[j];
  }

  void _openChapter(Chapter c) =>
      context.pushReplacement(MangaRoutes.reader(widget.mangaKey, c.url));

  void _turn(int delta, int total, MangaReadingMode mode) {
    final pager = _pager;
    if (pager == null) return;
    final target = _page + delta;
    if (target < 0) {
      final prev = _neighbour(-1);
      if (prev != null) _openChapter(prev);
    } else if (target >= total) {
      final next = _neighbour(1);
      if (next != null) _openChapter(next);
    } else {
      pager.jumpToPage(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final manga = ref.watch(mangaCacheProvider)[widget.mangaKey];
    final mode = ref.watch(mangaSettingsProvider.select((s) => s.mode));
    final pagesAsync = ref.watch(chapterPagesProvider(_ref));
    final chapter = ref
        .watch(chaptersProvider(widget.mangaKey))
        .value
        ?.where((c) => c.url == widget.chapterUrl)
        .firstOrNull;

    return Scaffold(
      backgroundColor: Colors.black,
      body: manga == null
          ? const Center(child: Text('Not found.'))
          : pagesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => MangaErrorView(
                error: e,
                onRetry: () => ref.invalidate(chapterPagesProvider(_ref)),
              ),
              data: (pages) {
                if (pages.isEmpty) {
                  return const Center(
                    child: Text('This chapter has no pages.'),
                  );
                }
                final total = pages.length;
                if (!_restored) {
                  _restored = true;
                  _page = _page.clamp(0, total - 1);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _onPage(_page, total);
                    if (mode == MangaReadingMode.vertical &&
                        _strip.hasClients &&
                        _page > 0) {
                      _strip.jumpTo(
                        _strip.position.maxScrollExtent * _page / (total - 1),
                      );
                    }
                  });
                }
                return Stack(
                  children: [
                    Positioned.fill(
                      child: mode == MangaReadingMode.vertical
                          ? _vertical(manga, pages)
                          : _paged(manga, pages, mode),
                    ),
                    if (_ui)
                      _Overlay(
                        title: manga.title,
                        chapter: chapter?.name ?? '',
                        page: _page,
                        total: total,
                        mode: mode,
                        onSeek: (p) {
                          if (mode == MangaReadingMode.vertical) {
                            _strip.jumpTo(
                              _strip.position.maxScrollExtent * p / (total - 1),
                            );
                          } else {
                            _pager?.jumpToPage(p);
                          }
                        },
                        onPrev: _neighbour(-1) == null
                            ? null
                            : () => _openChapter(_neighbour(-1)!),
                        onNext: _neighbour(1) == null
                            ? null
                            : () => _openChapter(_neighbour(1)!),
                      ),
                    if (!_ui)
                      Positioned(
                        bottom: 8,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Text(
                            '${_page + 1} / $total',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              shadows: [Shadow(blurRadius: 4)],
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

  Widget _paged(Manga manga, List<ReaderPage> pages, MangaReadingMode mode) {
    _pager ??= PageController(initialPage: _page);
    final rtl = mode == MangaReadingMode.rightToLeft;
    return LayoutBuilder(
      builder: (context, box) => GestureDetector(
        // Tap zones: outer thirds turn pages, middle toggles controls.
        onTapUp: (d) {
          final x = d.localPosition.dx / box.maxWidth;
          if (x > 1 / 3 && x < 2 / 3) {
            setState(() => _ui = !_ui);
          } else {
            final forward = (x >= 2 / 3) != rtl;
            _turn(forward ? 1 : -1, pages.length, mode);
          }
        },
        child: PageView.builder(
          controller: _pager,
          reverse: rtl,
          allowImplicitScrolling: true,
          itemCount: pages.length,
          onPageChanged: (i) => _onPage(i, pages.length),
          itemBuilder: (context, i) => InteractiveViewer(
            maxScale: 4,
            child: _PageImage(sourceId: manga.sourceId, page: pages[i]),
          ),
        ),
      ),
    );
  }

  Widget _vertical(Manga manga, List<ReaderPage> pages) {
    final next = _neighbour(1);
    return GestureDetector(
      onTap: () => setState(() => _ui = !_ui),
      child: ListView.builder(
        controller: _strip,
        cacheExtent: 2500,
        itemCount: pages.length + 1,
        itemBuilder: (context, i) {
          if (i == pages.length) {
            return Padding(
              padding: const EdgeInsets.all(32),
              child: next == null
                  ? const Center(child: Text('Last chapter'))
                  : FilledButton.icon(
                      onPressed: () => _openChapter(next),
                      icon: const Icon(Icons.skip_next),
                      label: Text('Next: ${next.name}'),
                    ),
            );
          }
          return _PageImage(
            sourceId: manga.sourceId,
            page: pages[i],
            minHeight: 400,
          );
        },
      ),
    );
  }
}

class _PageImage extends ConsumerWidget {
  const _PageImage({
    required this.sourceId,
    required this.page,
    this.minHeight,
  });

  final String sourceId;
  final ReaderPage page;
  final double? minHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (sourceId: sourceId, page: page);
    return ref
        .watch(pageImageProvider(key))
        .when(
          loading: () => SizedBox(
            height: minHeight ?? double.infinity,
            child: Center(
              child: Text(
                '${page.index + 1}',
                style: const TextStyle(color: Colors.white24, fontSize: 32),
              ),
            ),
          ),
          error: (e, _) => SizedBox(
            height: minHeight ?? double.infinity,
            child: Center(
              child: TextButton.icon(
                onPressed: () => ref.invalidate(pageImageProvider(key)),
                icon: const Icon(Icons.refresh),
                label: Text('Page ${page.index + 1} failed · Retry'),
              ),
            ),
          ),
          data: (path) => Image.file(
            File(path),
            fit: minHeight == null ? BoxFit.contain : BoxFit.fitWidth,
            width: double.infinity,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => SizedBox(
              height: minHeight ?? 200,
              child: const Center(child: Icon(Icons.broken_image)),
            ),
          ),
        );
  }
}

class _Overlay extends ConsumerWidget {
  const _Overlay({
    required this.title,
    required this.chapter,
    required this.page,
    required this.total,
    required this.mode,
    required this.onSeek,
    this.onPrev,
    this.onNext,
  });

  final String title;
  final String chapter;
  final int page;
  final int total;
  final MangaReadingMode mode;
  final ValueChanged<int> onSeek;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Material(
          color: const Color(0xEE1C1C1E),
          child: SafeArea(
            bottom: false,
            child: ListTile(
              leading: const BackButton(),
              title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(chapter, maxLines: 1),
            ),
          ),
        ),
        const Spacer(),
        Material(
          color: const Color(0xEE1C1C1E),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Previous chapter',
                        onPressed: onPrev,
                        icon: const Icon(Icons.skip_previous),
                      ),
                      Text('${page + 1}'),
                      Expanded(
                        child: total > 1
                            ? Slider(
                                value: page.toDouble(),
                                max: (total - 1).toDouble(),
                                divisions: total - 1,
                                activeColor: mangaAccent,
                                onChanged: (v) => onSeek(v.round()),
                              )
                            : const SizedBox(),
                      ),
                      Text('$total'),
                      IconButton(
                        tooltip: 'Next chapter',
                        onPressed: onNext,
                        icon: const Icon(Icons.skip_next),
                      ),
                    ],
                  ),
                  SegmentedButton<MangaReadingMode>(
                    showSelectedIcon: false,
                    segments: [
                      for (final m in MangaReadingMode.values)
                        ButtonSegment(value: m, label: Text(m.label)),
                    ],
                    selected: {mode},
                    onSelectionChanged: (v) => ref
                        .read(mangaSettingsProvider.notifier)
                        .setMode(v.first),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
