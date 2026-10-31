import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/widgets/dialogs.dart';
import '../../books_routes.dart';
import '../../domain/entities/book.dart';
import '../providers/books_providers.dart';

const booksAccent = Color(0xFFE0A33A);

/// Book cover (page 1) or a generated placeholder.
class BookCover extends ConsumerWidget {
  const BookCover({super.key, required this.book, this.radius = 8});

  final Book book;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cover = book.coverFileName;
    final path = cover == null
        ? null
        : ref.read(booksRepositoryProvider).absolutePath(cover);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: AspectRatio(
        aspectRatio: 0.7,
        child: path != null
            ? Image.file(
                File(path),
                fit: BoxFit.cover,
                cacheWidth: 360,
                errorBuilder: (_, _, _) => _Placeholder(book.title),
              )
            : _Placeholder(book.title),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5A4220), Color(0xFF2B2118)],
        ),
      ),
      padding: const EdgeInsets.all(10),
      alignment: Alignment.center,
      child: Text(
        title,
        textAlign: TextAlign.center,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Thin reading-progress bar.
class BookProgressBar extends StatelessWidget {
  const BookProgressBar({super.key, required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: book.isStarted ? book.progress : 0,
        minHeight: 3,
        color: booksAccent,
        backgroundColor: Colors.white12,
      ),
    );
  }
}

String progressLabel(Book book) {
  if (!book.isStarted) {
    return tr('New · {pageCount} pages', {'pageCount': book.pageCount});
  }
  if (book.lastPage >= book.pageCount) return tr('Finished');
  return '${(book.progress * 100).round()}% · p. ${book.lastPage}/${book.pageCount}';
}

class BookCard extends ConsumerWidget {
  const BookCard({super.key, required this.book});

  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => context.push(BooksRoutes.reader(book.id)),
      onLongPress: () => showBookActions(context, ref, book),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Hero(
              tag: 'book-${book.id}',
              child: BookCover(book: book),
            ),
            const SizedBox(height: 8),
            Text(
              book.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5, height: 1.2),
            ),
            const SizedBox(height: 6),
            BookProgressBar(book: book),
            const SizedBox(height: 4),
            Text(
              progressLabel(book),
              maxLines: 1,
              style: const TextStyle(fontSize: 11.5, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

/// Lets the user pick a shelf (or create one). Returns its id.
Future<String?> pickShelf(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  String? current,
}) async {
  const newShelf = '__new__';
  final shelves = ref.read(booksLibraryProvider).shelves;
  final choice = await showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(title),
      children: [
        for (final s in shelves)
          SimpleDialogOption(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            onPressed: () => Navigator.pop(context, s.id),
            child: Row(
              children: [
                Icon(
                  s.id == current ? Icons.radio_button_checked : Icons.shelves,
                  size: 20,
                  color: booksAccent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(s.name, style: const TextStyle(fontSize: 16)),
                ),
              ],
            ),
          ),
        SimpleDialogOption(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          onPressed: () => Navigator.pop(context, newShelf),
          child: Row(
            children: [
              Icon(Icons.add, size: 20),
              SizedBox(width: 12),
              Text(tr('New shelf…'), style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
      ],
    ),
  );
  if (choice != newShelf || !context.mounted) return choice;

  final name = await showTextInputDialog(
    context,
    title: tr('New shelf'),
    hint: tr('e.g. Novels, Study, Manuals'),
    confirmLabel: tr('Create'),
  );
  if (name == null) return null;
  return (await ref.read(booksLibraryProvider.notifier).addShelf(name)).id;
}

/// Picks PDFs and imports them into a shelf ([shelfId] or asked).
Future<void> importBooks(
  BuildContext context,
  WidgetRef ref, {
  String? shelfId,
}) async {
  final picked = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
  );
  if (picked.isEmpty || !context.mounted) return;

  final targetShelf =
      shelfId ??
      await pickShelf(context, ref, title: tr('Add to which shelf?'));
  if (targetShelf == null || !context.mounted) return;

  final files = [
    for (final f in picked)
      if (f.path != null) (path: f.path!, name: f.name),
  ];

  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(minutes: 5),
      content: Row(
        children: [
          const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 16),
          Text(
            files.length == 1
                ? tr('Importing 1 book…')
                : tr('Importing {count} books…', {'count': files.length}),
          ),
        ],
      ),
    ),
  );

  final report = await ref
      .read(booksLibraryProvider.notifier)
      .importFiles(targetShelf, files);
  await FilePicker.clearTemporaryFiles();

  messenger.hideCurrentSnackBar();
  final ok = report.imported.length;
  final failed = report.failures.length;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        failed == 0
            ? (ok == 1
                  ? tr('Added 1 book.')
                  : tr('Added {ok} books.', {'ok': ok}))
            : tr('Added {ok}, {failed} failed: {details}', {
                'ok': ok,
                'failed': failed,
                'details': report.failures.entries
                    .map((e) => '${e.key} (${e.value})')
                    .join(', '),
              }),
      ),
    ),
  );
}

/// Long-press menu for a book.
Future<void> showBookActions(
  BuildContext context,
  WidgetRef ref,
  Book book,
) async {
  final library = ref.read(booksLibraryProvider);
  final notifier = ref.read(booksLibraryProvider.notifier);
  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              book.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              tr('{shelf} · {pages} pages · {size}', {
                'shelf': library.shelfById(book.shelfId)?.name ?? '',
                'pages': book.pageCount,
                'size': _size(book.fileSize),
              }),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.menu_book),
            title: Text(
              book.isStarted ? tr('Continue reading') : tr('Start reading'),
            ),
            onTap: () => Navigator.pop(context, 'open'),
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: Text(tr('Rename')),
            onTap: () => Navigator.pop(context, 'rename'),
          ),
          ListTile(
            leading: const Icon(Icons.drive_file_move_outline),
            title: Text(tr('Move to shelf')),
            onTap: () => Navigator.pop(context, 'move'),
          ),
          if (book.isStarted)
            ListTile(
              leading: const Icon(Icons.restart_alt),
              title: Text(tr('Reset progress')),
              onTap: () => Navigator.pop(context, 'reset'),
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(tr('Delete')),
            onTap: () => Navigator.pop(context, 'delete'),
          ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;

  switch (action) {
    case 'open':
      context.push(BooksRoutes.reader(book.id));
    case 'rename':
      final name = await showTextInputDialog(
        context,
        title: tr('Rename book'),
        initialValue: book.title,
      );
      if (name != null) await notifier.updateBook(book.copyWith(title: name));
    case 'move':
      final shelf = await pickShelf(
        context,
        ref,
        title: tr('Move to'),
        current: book.shelfId,
      );
      if (shelf != null) {
        await notifier.updateBook(book.copyWith(shelfId: shelf));
      }
    case 'reset':
      await notifier.updateBook(
        Book(
          id: book.id,
          title: book.title,
          shelfId: book.shelfId,
          fileName: book.fileName,
          coverFileName: book.coverFileName,
          pageCount: book.pageCount,
          fileSize: book.fileSize,
          addedAt: book.addedAt,
        ),
      );
    case 'delete':
      final ok = await showConfirmDialog(
        context,
        title: tr('Delete "{title}"?', {'title': book.title}),
        message: tr(
          'The PDF, your progress and its bookmarks will be removed from MyKit.',
        ),
      );
      if (ok) await notifier.deleteBook(book.id);
  }
}

String _size(int bytes) {
  if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
  return '${(bytes / 1024).round()} KB';
}
