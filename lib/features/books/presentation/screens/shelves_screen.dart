import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/widgets/dialogs.dart';
import '../providers/books_providers.dart';
import '../widgets/book_widgets.dart';

/// Create, rename and delete shelves; import straight into one.
class ShelvesScreen extends ConsumerWidget {
  const ShelvesScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = await showTextInputDialog(
      context,
      title: tr('New shelf'),
      hint: tr('e.g. Novels, Study, Manuals'),
      confirmLabel: tr('Create'),
    );
    if (name != null) {
      await ref.read(booksLibraryProvider.notifier).addShelf(name);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(booksLibraryProvider);
    final notifier = ref.read(booksLibraryProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(tr('Shelves'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          for (final shelf in library.shelves)
            Builder(
              builder: (context) {
                final books = library.booksIn(shelf.id);
                final pages = books.fold<int>(0, (n, b) => n + b.pageCount);
                return ListTile(
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: booksAccent.withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.shelves, color: booksAccent),
                  ),
                  title: Text(shelf.name),
                  subtitle: Text(
                    tr(
                      books.length == 1
                          ? '1 book · {pages} pages'
                          : '{count} books · {pages} pages',
                      {'count': books.length, 'pages': pages},
                    ),
                    style: const TextStyle(color: Colors.white54),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) async {
                      switch (action) {
                        case 'import':
                          await importBooks(context, ref, shelfId: shelf.id);
                        case 'rename':
                          final name = await showTextInputDialog(
                            context,
                            title: tr('Rename shelf'),
                            initialValue: shelf.name,
                          );
                          if (name != null) {
                            await notifier.renameShelf(shelf.id, name);
                          }
                        case 'delete':
                          final ok = await showConfirmDialog(
                            context,
                            title: tr('Delete "{name}"?', {'name': shelf.name}),
                            message: books.isEmpty
                                ? tr('This shelf is empty.')
                                : books.length == 1
                                ? tr(
                                    'Its 1 book will be deleted too. Move it to another shelf first to keep it.',
                                  )
                                : tr(
                                    'Its {count} books will be deleted too. Move them to another shelf first to keep them.',
                                    {'count': books.length},
                                  ),
                          );
                          if (ok) await notifier.deleteShelf(shelf.id);
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'import',
                        child: Text(tr('Import PDFs here')),
                      ),
                      PopupMenuItem(value: 'rename', child: Text(tr('Rename'))),
                      PopupMenuItem(value: 'delete', child: Text(tr('Delete'))),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        shape: const StadiumBorder(),
        backgroundColor: booksAccent,
        foregroundColor: Colors.black,
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.add),
        label: Text(tr('New shelf')),
      ),
    );
  }
}
