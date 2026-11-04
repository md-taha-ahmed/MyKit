import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/widgets/dialogs.dart';
import '../../domain/entities/book.dart';
import '../providers/books_providers.dart';
import 'book_widgets.dart';

// ---------------------------------------------------------------------------
// Reading settings
// ---------------------------------------------------------------------------

Future<void> showReaderSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => Consumer(
      builder: (context, ref, _) {
        final settings = ref.watch(readerSettingsProvider);
        final notifier = ref.read(readerSettingsProvider.notifier);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Label(tr('Scrolling')),
                SegmentedButton<ReaderScrollMode>(
                  segments: [
                    ButtonSegment(
                      value: ReaderScrollMode.vertical,
                      icon: Icon(Icons.swap_vert),
                      label: Text(tr('Vertical')),
                    ),
                    ButtonSegment(
                      value: ReaderScrollMode.horizontal,
                      icon: Icon(Icons.swap_horiz),
                      label: Text(tr('Horizontal')),
                    ),
                  ],
                  selected: {settings.scrollMode},
                  onSelectionChanged: (v) =>
                      notifier.update((s) => s.copyWith(scrollMode: v.first)),
                ),
                const SizedBox(height: 6),
                Text(
                  settings.scrollMode.description,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 20),
                _Label(tr('Page colour')),
                Row(
                  children: [
                    for (final mode in ReaderColorMode.values)
                      Expanded(
                        child: _ColorOption(
                          mode: mode,
                          selected: settings.colorMode == mode,
                          onTap: () => notifier.update(
                            (s) => s.copyWith(colorMode: mode),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: const TextStyle(color: booksAccent, fontWeight: FontWeight.w600),
    ),
  );
}

class _ColorOption extends StatelessWidget {
  const _ColorOption({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final ReaderColorMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (paper, ink) = switch (mode) {
      ReaderColorMode.light => (Colors.white, Colors.black),
      ReaderColorMode.dark => (
        const Color(0xFF0D0D0D),
        const Color(0xFFE6E6E6),
      ),
      ReaderColorMode.sepia => (
        const Color(0xFFF4ECD8),
        const Color(0xFF1C160F),
      ),
    };
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: paper,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? booksAccent : Colors.white24,
            width: selected ? 3 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              tr('Aa'),
              style: TextStyle(
                color: ink,
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(mode.label, style: TextStyle(color: ink, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Go to page
// ---------------------------------------------------------------------------

Future<int?> showGoToPageDialog(
  BuildContext context, {
  required int current,
  required int pageCount,
}) {
  final controller = TextEditingController(text: '$current');
  int? parse() {
    final n = int.tryParse(controller.text.trim());
    return n != null && n >= 1 && n <= pageCount ? n : null;
  }

  return showDialog<int>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(tr('Go to page')),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            helperText: '1 – $pageCount',
            errorText: controller.text.isEmpty || parse() != null
                ? null
                : tr('Enter a page between 1 and {pageCount}', {
                    'pageCount': pageCount,
                  }),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) {
            final n = parse();
            if (n != null) Navigator.pop(context, n);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: parse() == null
                ? null
                : () => Navigator.pop(context, parse()),
            child: Text(tr('Go')),
          ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Bookmarks
// ---------------------------------------------------------------------------

/// Returns the page to jump to, if one was tapped.
Future<int?> showBookmarksSheet(
  BuildContext context, {
  required Book book,
  required int currentPage,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .6,
      maxChildSize: .95,
      builder: (context, scroll) => Consumer(
        builder: (context, ref, _) {
          final marks = ref.watch(bookBookmarksProvider(book.id));
          final notifier = ref.read(bookmarksProvider.notifier);
          final isMarked = marks.any((b) => b.page == currentPage);

          return ListView(
            controller: scroll,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr('Bookmarks · {length}', {'length': marks.length}),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => notifier.toggle(book.id, currentPage),
                      icon: Icon(
                        isMarked ? Icons.bookmark_remove : Icons.bookmark_add,
                      ),
                      label: Text(
                        isMarked
                            ? tr('Remove p. {currentPage}', {
                                'currentPage': currentPage,
                              })
                            : tr('Bookmark p. {currentPage}', {
                                'currentPage': currentPage,
                              }),
                      ),
                    ),
                  ],
                ),
              ),
              if (marks.isEmpty)
                Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    tr(
                      'No bookmarks yet.\nTap the bookmark icon while reading to save a page.',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              for (final mark in marks)
                ListTile(
                  onTap: () => Navigator.pop(context, mark.page),
                  leading: Icon(
                    Icons.bookmark,
                    color: mark.page == currentPage
                        ? booksAccent
                        : Colors.white54,
                  ),
                  title: Text(tr('Page {page}', {'page': mark.page})),
                  subtitle: Text(
                    mark.note.isEmpty
                        ? DateFormat('d MMM y').format(mark.createdAt)
                        : mark.note,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: tr('Edit note'),
                        icon: const Icon(Icons.edit_note),
                        onPressed: () async {
                          final note = await showTextInputDialog(
                            context,
                            title: tr('Note for page {page}', {
                              'page': mark.page,
                            }),
                            initialValue: mark.note,
                            hint: tr('What is on this page?'),
                          );
                          if (note != null) {
                            await notifier.updateNote(mark.id, note);
                          }
                        },
                      ),
                      IconButton(
                        tooltip: tr('Delete'),
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => notifier.remove(mark.id),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Table of contents
// ---------------------------------------------------------------------------

Future<int?> showContentsSheet(BuildContext context, PdfDocument document) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .7,
      maxChildSize: .95,
      builder: (context, scroll) => FutureBuilder<List<PdfOutlineNode>>(
        future: document.loadOutline(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = <(PdfOutlineNode, int)>[];
          void walk(List<PdfOutlineNode> nodes, int depth) {
            for (final n in nodes) {
              entries.add((n, depth));
              walk(n.children, depth + 1);
            }
          }

          walk(snap.data!, 0);
          if (entries.isEmpty) {
            return Center(
              child: Text(
                tr('This PDF has no table of contents.'),
                style: TextStyle(color: Colors.white54),
              ),
            );
          }
          return ListView.builder(
            controller: scroll,
            itemCount: entries.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    tr('Contents'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                );
              }
              final (node, depth) = entries[i - 1];
              final page = node.dest?.pageNumber;
              return ListTile(
                contentPadding: EdgeInsets.only(
                  left: 20 + depth * 16.0,
                  right: 20,
                ),
                dense: depth > 0,
                enabled: page != null,
                title: Text(
                  node.title,
                  style: TextStyle(
                    fontWeight: depth == 0 ? FontWeight.w600 : null,
                  ),
                ),
                trailing: page == null
                    ? null
                    : Text(
                        '$page',
                        style: const TextStyle(color: Colors.white54),
                      ),
                onTap: page == null ? null : () => Navigator.pop(context, page),
              );
            },
          );
        },
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Search
// ---------------------------------------------------------------------------

Future<int?> showSearchSheet(BuildContext context, PdfDocument document) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _SearchSheet(document: document),
  );
}

class _SearchHit {
  const _SearchHit(this.page, this.snippet, this.start, this.length);

  final int page;
  final String snippet;

  /// Match position inside [snippet].
  final int start;
  final int length;
}

class _SearchSheet extends StatefulWidget {
  const _SearchSheet({required this.document});

  final PdfDocument document;

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  static const _maxHits = 300;

  final _query = TextEditingController();
  final _hits = <_SearchHit>[];
  int _session = 0;
  int _scanned = 0;
  bool _running = false;

  @override
  void dispose() {
    _session++; // cancels a running search
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final needle = _query.text.trim().toLowerCase();
    if (needle.isEmpty) return;
    final session = ++_session;
    setState(() {
      _hits.clear();
      _scanned = 0;
      _running = true;
    });

    final pages = widget.document.pages;
    for (final page in pages) {
      if (session != _session) return;
      final text = (await page.loadText())?.fullText ?? '';
      final lower = text.toLowerCase();
      var from = 0;
      while (_hits.length < _maxHits) {
        final at = lower.indexOf(needle, from);
        if (at < 0) break;
        final s = (at - 40).clamp(0, text.length);
        final e = (at + needle.length + 60).clamp(0, text.length);
        final prefix = s > 0 ? '…' : '';
        final snippet =
            '$prefix${text.substring(s, e).replaceAll(RegExp(r'\s+'), ' ')}…';
        final matchStart =
            prefix.length +
            text.substring(s, at).replaceAll(RegExp(r'\s+'), ' ').length;
        _hits.add(
          _SearchHit(page.pageNumber, snippet, matchStart, needle.length),
        );
        from = at + needle.length;
      }
      if (!mounted || session != _session) return;
      setState(() => _scanned = page.pageNumber);
      if (_hits.length >= _maxHits) break;
    }
    if (mounted && session == _session) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.document.pages.length;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _query,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: tr('Search in this book'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: _search,
                  ),
                ),
                onSubmitted: (_) => _search(),
              ),
            ),
            if (_running)
              LinearProgressIndicator(
                value: total == 0 ? null : _scanned / total,
                color: booksAccent,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _session == 0
                      ? tr('Searches the text of every page.')
                      : _running
                      ? tr(
                          'Searching… page {_scanned} of {total} · {length} found',
                          {
                            '_scanned': _scanned,
                            'total': total,
                            'length': _hits.length,
                          },
                        )
                      : '${_hits.length}${_hits.length >= _maxHits ? '+' : ''} results',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _hits.length,
                itemBuilder: (context, i) {
                  final hit = _hits[i];
                  final end = (hit.start + hit.length).clamp(
                    0,
                    hit.snippet.length,
                  );
                  final start = hit.start.clamp(0, end);
                  return ListTile(
                    onTap: () => Navigator.pop(context, hit.page),
                    leading: Text(
                      'p. ${hit.page}',
                      style: const TextStyle(color: booksAccent),
                    ),
                    title: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: hit.snippet.substring(0, start)),
                          TextSpan(
                            text: hit.snippet.substring(start, end),
                            style: const TextStyle(
                              backgroundColor: Color(0x66E0A33A),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(text: hit.snippet.substring(end)),
                        ],
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
