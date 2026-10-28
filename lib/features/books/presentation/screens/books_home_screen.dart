import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/dialogs.dart';
import '../../books_routes.dart';
import '../../domain/entities/book.dart';
import '../providers/books_providers.dart';
import '../widgets/book_widgets.dart';

/// Library: continue reading, shelves and the book grid.
class BooksHomeScreen extends ConsumerStatefulWidget {
  const BooksHomeScreen({super.key});

  @override
  ConsumerState<BooksHomeScreen> createState() => _BooksHomeScreenState();
}

class _BooksHomeScreenState extends ConsumerState<BooksHomeScreen> {
  final _search = TextEditingController();
  bool _searching = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _sort() async {
    final current = ref.read(readerSettingsProvider).sort;
    final choice = await showDialog<BookSort>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Sort books'),
        children: [
          for (final s in BookSort.values)
            SimpleDialogOption(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              onPressed: () => Navigator.pop(context, s),
              child: Row(
                children: [
                  Icon(
                    s == current
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(s.label, style: const TextStyle(fontSize: 16)),
                ],
              ),
            ),
        ],
      ),
    );
    if (choice != null) {
      ref
          .read(readerSettingsProvider.notifier)
          .update((s) => s.copyWith(sort: choice));
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(booksLibraryProvider);
    final chosen = ref.watch(selectedShelfProvider);
    final shelfId = chosen != null && library.shelfById(chosen) != null
        ? chosen
        : null;
    final query = (shelfId: shelfId, search: _search.text);
    final books = ref.watch(filteredBooksProvider(query));
    final continueReading = ref.watch(continueReadingProvider);
    final showContinue =
        continueReading.isNotEmpty && shelfId == null && _search.text.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search books',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                onChanged: (_) => setState(() {}),
              )
            : const Text('Books'),
        actions: [
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) _search.clear();
            }),
          ),
          IconButton(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort),
            onPressed: _sort,
          ),
          IconButton(
            tooltip: 'Manage shelves',
            icon: const Icon(Icons.shelves),
            onPressed: () => context.push(BooksRoutes.shelves),
          ),
        ],
      ),
      body: library.books.isEmpty
          ? _EmptyLibrary(onImport: () => importBooks(context, ref))
          : CustomScrollView(
              slivers: [
                if (showContinue) ...[
                  const _SectionTitle('Continue reading'),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 128,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: continueReading.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (context, i) =>
                            _ContinueCard(book: continueReading[i]),
                      ),
                    ),
                  ),
                ],
                SliverToBoxAdapter(child: _ShelfChips(selected: shelfId)),
                if (books.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        _search.text.isEmpty
                            ? 'This shelf is empty.\nTap + to import PDFs.'
                            : 'No books match "${_search.text}".',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white54),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 160,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            childAspectRatio: .46,
                          ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => BookCard(book: books[i]),
                        childCount: books.length,
                      ),
                    ),
                  ),
              ],
            ),
      floatingActionButton: library.books.isEmpty
          ? null
          : FloatingActionButton.extended(
              shape: const StadiumBorder(),
              backgroundColor: booksAccent,
              foregroundColor: Colors.black,
              onPressed: () => importBooks(context, ref, shelfId: shelfId),
              icon: const Icon(Icons.add),
              label: const Text('Import PDF'),
            ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Text(
        text,
        style: const TextStyle(
          color: booksAccent,
          fontWeight: FontWeight.w700,
          fontSize: 13,
          letterSpacing: .5,
        ),
      ),
    ),
  );
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(BooksRoutes.reader(book.id)),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                SizedBox(width: 74, child: BookCover(book: book, radius: 6)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Text(
                        progressLabel(book),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white60,
                        ),
                      ),
                      const SizedBox(height: 6),
                      BookProgressBar(book: book),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShelfChips extends ConsumerWidget {
  const _ShelfChips({required this.selected});

  final String? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(booksLibraryProvider);
    final notifier = ref.read(selectedShelfProvider.notifier);

    Widget chip(String? id, String label, int count) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text('$label  $count'),
        selected: selected == id,
        showCheckmark: false,
        onSelected: (_) => notifier.select(id),
      ),
    );

    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        children: [
          chip(null, 'All', library.books.length),
          for (final s in library.shelves)
            chip(s.id, s.name, library.booksIn(s.id).length),
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: const Text('Shelf'),
            onPressed: () async {
              final name = await showTextInputDialog(
                context,
                title: 'New shelf',
                hint: 'e.g. Novels, Study, Manuals',
                confirmLabel: 'Create',
              );
              if (name == null) return;
              final shelf = await ref
                  .read(booksLibraryProvider.notifier)
                  .addShelf(name);
              notifier.select(shelf.id);
            },
          ),
        ],
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_stories, size: 72, color: Colors.white24),
            const SizedBox(height: 16),
            Text(
              'Your library is empty',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Import PDFs into shelves. MyKit remembers your page, '
              'keeps bookmarks and has a dark reading mode.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: booksAccent,
                foregroundColor: Colors.black,
              ),
              onPressed: onImport,
              icon: const Icon(Icons.file_open),
              label: const Text('Import PDF'),
            ),
          ],
        ),
      ),
    );
  }
}
