import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../../core/i18n/i18n.dart';
import '../../domain/entities/book.dart';
import '../providers/books_providers.dart';
import '../widgets/book_widgets.dart';
import '../widgets/reader_colors.dart';
import '../widgets/reader_sheets.dart';

/// PDF reader: remembers the page, bookmarks, vertical/horizontal layouts,
/// light/dark/sepia page colours. Tap the page to show or hide the controls.
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.bookId});

  final String bookId;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  final _pdfController = PdfViewerController();
  PageController? _pageController;
  PdfDocumentRef? _docRef;

  late int _page;
  bool _uiVisible = true;
  bool _zoomed = false; // horizontal mode: lock swiping while zoomed in
  double? _sliderDrag;

  @override
  void initState() {
    super.initState();
    final book = ref.read(booksLibraryProvider).bookById(widget.bookId);
    _page = book?.lastPage ?? 1;
    // Marks the book as opened (shows up in "Continue reading").
    Future.microtask(
      () => ref
          .read(booksLibraryProvider.notifier)
          .saveProgress(widget.bookId, _page),
    );
  }

  @override
  void dispose() {
    _pageController?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _onPageChanged(int page) {
    if (page == _page) return;
    setState(() => _page = page);
    ref.read(booksLibraryProvider.notifier).saveProgress(widget.bookId, page);
  }

  void _toggleUi() {
    setState(() => _uiVisible = !_uiVisible);
    SystemChrome.setEnabledSystemUIMode(
      _uiVisible ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
  }

  Future<void> _goTo(int page) async {
    final mode = ref.read(readerSettingsProvider).scrollMode;
    if (mode == ReaderScrollMode.horizontal) {
      _pageController?.jumpToPage(page - 1);
    } else if (_pdfController.isReady) {
      await _pdfController.goToPage(
        pageNumber: page,
        anchor: PdfPageAnchor.top,
      );
    }
    _onPageChanged(page);
  }

  Future<void> _jumpFrom(Future<int?> sheet) async {
    final page = await sheet;
    if (page != null) await _goTo(page);
  }

  Future<void> _toggleBookmark() async {
    final added = await ref
        .read(bookmarksProvider.notifier)
        .toggle(widget.bookId, _page);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(
            added
                ? tr('Page {_page} bookmarked', {'_page': _page})
                : tr('Bookmark removed'),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final book = ref.watch(booksLibraryProvider).bookById(widget.bookId);
    final settings = ref.watch(readerSettingsProvider);
    final documentAsync = ref.watch(bookDocumentProvider(widget.bookId));

    if (book == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(tr('This book was removed.'))),
      );
    }

    final colors = ReaderColors.of(settings.colorMode);
    final bookmarked = ref
        .watch(bookBookmarksProvider(book.id))
        .any((b) => b.page == _page);

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1C),
      body: documentAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              tr('Could not open this PDF.\n{e}', {'e': e}),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (document) {
          final pageCount = document.pages.length;
          return Stack(
            children: [
              Positioned.fill(
                child: colors.apply(
                  ColoredBox(
                    color: colors.viewerBackground,
                    child: settings.scrollMode == ReaderScrollMode.vertical
                        ? _vertical(document, colors)
                        : _horizontal(document),
                  ),
                ),
              ),
              if (bookmarked && !_uiVisible)
                const Positioned(
                  top: 0,
                  right: 24,
                  child: Icon(Icons.bookmark, color: booksAccent, size: 32),
                ),
              _TopBar(
                visible: _uiVisible,
                title: book.title,
                subtitle: tr('Page {_page} of {pageCount}', {
                  '_page': _page,
                  'pageCount': pageCount,
                }),
                bookmarked: bookmarked,
                onBookmark: _toggleBookmark,
                onSearch: () => _jumpFrom(showSearchSheet(context, document)),
                onMenu: (action) => switch (action) {
                  _Menu.contents => _jumpFrom(
                    showContentsSheet(context, document),
                  ),
                  _Menu.bookmarks => _jumpFrom(
                    showBookmarksSheet(context, book: book, currentPage: _page),
                  ),
                  _Menu.goTo => _jumpFrom(
                    showGoToPageDialog(
                      context,
                      current: _page,
                      pageCount: pageCount,
                    ),
                  ),
                  _Menu.settings => showReaderSettingsSheet(context),
                },
              ),
              _BottomBar(
                visible: _uiVisible,
                page: (_sliderDrag ?? _page.toDouble()).round(),
                pageCount: pageCount,
                sliderValue: _sliderDrag ?? _page.toDouble(),
                onSliderChanged: (v) => setState(() => _sliderDrag = v),
                onSliderEnd: (v) {
                  setState(() => _sliderDrag = null);
                  _goTo(v.round());
                },
                settings: settings,
                onScrollMode: () => ref
                    .read(readerSettingsProvider.notifier)
                    .update(
                      (s) => s.copyWith(
                        scrollMode: s.scrollMode == ReaderScrollMode.vertical
                            ? ReaderScrollMode.horizontal
                            : ReaderScrollMode.vertical,
                      ),
                    ),
                onColorMode: () => ref
                    .read(readerSettingsProvider.notifier)
                    .update(
                      (s) => s.copyWith(
                        colorMode:
                            ReaderColorMode.values[(s.colorMode.index + 1) %
                                ReaderColorMode.values.length],
                      ),
                    ),
                onBookmarks: () => _jumpFrom(
                  showBookmarksSheet(context, book: book, currentPage: _page),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // Vertical: continuous scroll with zoom, links and smooth rendering.
  Widget _vertical(PdfDocument document, ReaderColors colors) {
    _pageController?.dispose();
    _pageController = null;
    _docRef ??= PdfDocumentRefDirect(document, autoDispose: false);

    return PdfViewer(
      _docRef!,
      controller: _pdfController,
      initialPageNumber: _page,
      params: PdfViewerParams(
        backgroundColor: colors.viewerBackground,
        margin: 6,
        pageDropShadow: colors.pageShadow
            ? const BoxShadow(color: Colors.black54, blurRadius: 4)
            : null,
        onPageChanged: (page) {
          if (page != null) _onPageChanged(page);
        },
        onGeneralTap: (context, controller, details) {
          if (details.type == PdfViewerGeneralTapType.tap) {
            _toggleUi();
            return true;
          }
          return false;
        },
      ),
    );
  }

  // Horizontal: one page per screen, swipe to turn, pinch to zoom.
  Widget _horizontal(PdfDocument document) {
    _pageController ??= PageController(initialPage: _page - 1);
    return GestureDetector(
      onTap: _toggleUi,
      child: PageView.builder(
        controller: _pageController,
        physics: _zoomed
            ? const NeverScrollableScrollPhysics()
            : const PageScrollPhysics(),
        itemCount: document.pages.length,
        onPageChanged: (i) {
          _zoomed = false;
          _onPageChanged(i + 1);
        },
        itemBuilder: (context, i) => _ZoomablePage(
          document: document,
          pageNumber: i + 1,
          onZoomChanged: (zoomed) {
            if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
          },
        ),
      ),
    );
  }
}

class _ZoomablePage extends StatefulWidget {
  const _ZoomablePage({
    required this.document,
    required this.pageNumber,
    required this.onZoomChanged,
  });

  final PdfDocument document;
  final int pageNumber;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomablePage> createState() => _ZoomablePageState();
}

class _ZoomablePageState extends State<_ZoomablePage> {
  final _transform = TransformationController();
  TapDownDetails? _doubleTapAt;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _report() =>
      widget.onZoomChanged(_transform.value.getMaxScaleOnAxis() > 1.01);

  /// Double-tap: zoom 2.5× around the finger, or back to fit.
  void _onDoubleTap() {
    if (_transform.value.getMaxScaleOnAxis() > 1.01) {
      _transform.value = Matrix4.identity();
    } else {
      final p = _doubleTapAt?.localPosition ?? Offset.zero;
      const s = 2.5;
      _transform.value = Matrix4.identity()
        ..translateByDouble(-p.dx * (s - 1), -p.dy * (s - 1), 0, 1)
        ..scaleByDouble(s, s, 1, 1);
    }
    _report();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (d) => _doubleTapAt = d,
      onDoubleTap: _onDoubleTap,
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: 6,
        onInteractionEnd: (_) => _report(),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: PdfPageView(
            document: widget.document,
            pageNumber: widget.pageNumber,
            maximumDpi: 400,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overlay bars
// ---------------------------------------------------------------------------

enum _Menu { contents, bookmarks, goTo, settings }

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.visible,
    required this.title,
    required this.subtitle,
    required this.bookmarked,
    required this.onBookmark,
    required this.onSearch,
    required this.onMenu,
  });

  final bool visible;
  final String title;
  final String subtitle;
  final bool bookmarked;
  final VoidCallback onBookmark;
  final VoidCallback onSearch;
  final ValueChanged<_Menu> onMenu;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 200),
        offset: visible ? Offset.zero : const Offset(0, -1),
        child: Material(
          color: const Color(0xF0202022),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 60,
              child: Row(
                children: [
                  const BackButton(),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Colors.white60,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: bookmarked
                        ? tr('Remove bookmark')
                        : tr('Bookmark page'),
                    onPressed: onBookmark,
                    icon: Icon(
                      bookmarked ? Icons.bookmark : Icons.bookmark_border,
                      color: bookmarked ? booksAccent : null,
                    ),
                  ),
                  IconButton(
                    tooltip: tr('Search'),
                    onPressed: onSearch,
                    icon: const Icon(Icons.search),
                  ),
                  PopupMenuButton<_Menu>(
                    onSelected: onMenu,
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: _Menu.contents,
                        child: ListTile(
                          leading: Icon(Icons.toc),
                          title: Text(tr('Contents')),
                        ),
                      ),
                      PopupMenuItem(
                        value: _Menu.bookmarks,
                        child: ListTile(
                          leading: Icon(Icons.bookmarks_outlined),
                          title: Text(tr('Bookmarks')),
                        ),
                      ),
                      PopupMenuItem(
                        value: _Menu.goTo,
                        child: ListTile(
                          leading: Icon(Icons.pin_outlined),
                          title: Text(tr('Go to page')),
                        ),
                      ),
                      PopupMenuItem(
                        value: _Menu.settings,
                        child: ListTile(
                          leading: Icon(Icons.tune),
                          title: Text(tr('Reading settings')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.visible,
    required this.page,
    required this.pageCount,
    required this.sliderValue,
    required this.onSliderChanged,
    required this.onSliderEnd,
    required this.settings,
    required this.onScrollMode,
    required this.onColorMode,
    required this.onBookmarks,
  });

  final bool visible;
  final int page;
  final int pageCount;
  final double sliderValue;
  final ValueChanged<double> onSliderChanged;
  final ValueChanged<double> onSliderEnd;
  final ReaderSettings settings;
  final VoidCallback onScrollMode;
  final VoidCallback onColorMode;
  final VoidCallback onBookmarks;

  @override
  Widget build(BuildContext context) {
    final colorIcon = switch (settings.colorMode) {
      ReaderColorMode.light => Icons.light_mode,
      ReaderColorMode.dark => Icons.dark_mode,
      ReaderColorMode.sepia => Icons.coffee,
    };

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 200),
        offset: visible ? Offset.zero : const Offset(0, 1),
        child: Material(
          color: const Color(0xF0202022),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 44,
                        child: Text(
                          '$page',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Expanded(
                        child: pageCount > 1
                            ? Slider(
                                min: 1,
                                max: pageCount.toDouble(),
                                value: sliderValue.clamp(
                                  1,
                                  pageCount.toDouble(),
                                ),
                                activeColor: booksAccent,
                                onChanged: onSliderChanged,
                                onChangeEnd: onSliderEnd,
                              )
                            : const SizedBox(height: 48),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text(
                          '$pageCount',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white60),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _BarButton(
                        icon: settings.scrollMode == ReaderScrollMode.vertical
                            ? Icons.swap_vert
                            : Icons.swap_horiz,
                        label: settings.scrollMode.label,
                        onTap: onScrollMode,
                      ),
                      _BarButton(
                        icon: colorIcon,
                        label: settings.colorMode.label,
                        onTap: onColorMode,
                      ),
                      _BarButton(
                        icon: Icons.bookmarks_outlined,
                        label: tr('Bookmarks'),
                        onTap: onBookmarks,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11.5)),
          ],
        ),
      ),
    );
  }
}
