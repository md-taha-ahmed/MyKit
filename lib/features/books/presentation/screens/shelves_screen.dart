import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/dialogs.dart';
import '../providers/books_providers.dart';
import '../widgets/book_widgets.dart';

/// Create, rename and delete shelves; import straight into one.
class ShelvesScreen extends ConsumerWidget {
  const ShelvesScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = await showTextInputDialog(
      context,
      title: 'New shelf',
      hint: 'e.g. Novels, Study, Manuals',
      confirmLabel: 'Create',
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
      appBar: AppBar(title: const Text('Shelves')),
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
                    '${books.length} ${books.length == 1 ? 'book' : 'books'}'
                    ' · $pages pages',
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
                            title: 'Rename shelf',
                            initialValue: shelf.name,
                          );
                          if (name != null) {
                            await notifier.renameShelf(shelf.id, name);
                          }
                        case 'delete':
                          final ok = await showConfirmDialog(
                            context,
                            title: 'Delete "${shelf.name}"?',
                            message: books.isEmpty
                                ? 'This shelf is empty.'
                                : 'Its ${books.length} '
                                      '${books.length == 1 ? 'book' : 'books'} '
                                      'will be deleted too. Move them to '
                                      'another shelf first to keep them.',
                          );
                          if (ok) await notifier.deleteShelf(shelf.id);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'import',
                        child: Text('Import PDFs here'),
                      ),
                      PopupMenuItem(value: 'rename', child: Text('Rename')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
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
        label: const Text('New shelf'),
      ),
    );
  }
}
