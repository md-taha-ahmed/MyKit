import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/storage/app_directories.dart';
import '../../../../core/storage/shared_preferences_provider.dart';
import '../../../../core/utils/natural_sort.dart';
import '../../data/datasources/book_file_storage.dart';
import '../../data/datasources/books_local_data_source.dart';
import '../../data/repositories/books_repository_impl.dart';
import '../../domain/entities/book.dart';
import '../../domain/repositories/books_repository.dart';

const _uuid = Uuid();

// ---------------------------------------------------------------------------
// Dependencies
// ---------------------------------------------------------------------------

final booksRepositoryProvider = Provider<BooksRepository>((ref) {
  return BooksRepositoryImpl(
    BooksLocalDataSource(ref.watch(sharedPreferencesProvider)),
    BookFileStorage(ref.watch(appDocumentsDirectoryProvider)),
  );
});

// ---------------------------------------------------------------------------
// Library: shelves + books
// ---------------------------------------------------------------------------

class BooksLibrary {
  const BooksLibrary({required this.shelves, required this.books});

  final List<BookShelf> shelves;
  final List<Book> books;

  Book? bookById(String id) {
    for (final b in books) {
      if (b.id == id) return b;
    }
    return null;
  }

  BookShelf? shelfById(String id) {
    for (final s in shelves) {
      if (s.id == id) return s;
    }
    return null;
  }

  List<Book> booksIn(String shelfId) =>
      books.where((b) => b.shelfId == shelfId).toList();
}

/// Outcome of importing several files.
class ImportReport {
  const ImportReport({required this.imported, required this.failures});

  final List<Book> imported;

  /// File name → reason.
  final Map<String, String> failures;
}

final booksLibraryProvider =
    NotifierProvider<BooksLibraryNotifier, BooksLibrary>(
      BooksLibraryNotifier.new,
    );

class BooksLibraryNotifier extends Notifier<BooksLibrary> {
  BooksRepository get _repo => ref.read(booksRepositoryProvider);

  @override
  BooksLibrary build() {
    var shelves = _repo.getShelves();
    if (shelves.isEmpty) {
      shelves = [BookShelf(id: _uuid.v4(), name: 'My books')];
      _repo.saveShelves(shelves);
    }
    return BooksLibrary(shelves: shelves, books: _repo.getBooks());
  }

  Future<void> _set({List<BookShelf>? shelves, List<Book>? books}) async {
    state = BooksLibrary(
      shelves: shelves ?? state.shelves,
      books: books ?? state.books,
    );
    if (shelves != null) await _repo.saveShelves(shelves);
    if (books != null) await _repo.saveBooks(books);
  }

  // Shelves ------------------------------------------------------------------

  Future<BookShelf> addShelf(String name) async {
    final shelf = BookShelf(id: _uuid.v4(), name: name.trim());
    await _set(shelves: [...state.shelves, shelf]);
    return shelf;
  }

  Future<void> renameShelf(String id, String name) => _set(
    shelves: [
      for (final s in state.shelves)
        s.id == id ? s.copyWith(name: name.trim()) : s,
    ],
  );

  /// Deletes the shelf with its books (files and bookmarks included).
  Future<void> deleteShelf(String id) async {
    final doomed = state.booksIn(id);
    for (final b in doomed) {
      await _repo.deleteFiles(b);
    }
    await _set(
      shelves: state.shelves.where((s) => s.id != id).toList(),
      books: state.books.where((b) => b.shelfId != id).toList(),
    );
    if (state.shelves.isEmpty) await addShelf(tr('My books'));
    await ref
        .read(bookmarksProvider.notifier)
        .removeForBooks(doomed.map((b) => b.id).toSet());
  }

  // Books --------------------------------------------------------------------

  /// Copies each PDF into the library under [shelfId].
  Future<ImportReport> importFiles(
    String shelfId,
    List<({String path, String name})> files,
  ) async {
    final imported = <Book>[];
    final failures = <String, String>{};

    for (final file in files) {
      final id = _uuid.v4();
      try {
        final pdf = await _repo.importPdf(file.path, id);
        imported.add(
          Book(
            id: id,
            title: prettifyFileName(file.name),
            shelfId: shelfId,
            fileName: pdf.fileName,
            coverFileName: pdf.coverFileName,
            pageCount: pdf.pageCount,
            fileSize: pdf.fileSize,
            addedAt: DateTime.now(),
          ),
        );
      } on BookImportException catch (e) {
        failures[file.name] = e.message;
      } catch (e) {
        failures[file.name] = '$e';
      }
    }

    if (imported.isNotEmpty) await _set(books: [...state.books, ...imported]);
    return ImportReport(imported: imported, failures: failures);
  }

  Future<void> updateBook(Book book) =>
      _set(books: [for (final b in state.books) b.id == book.id ? book : b]);

  /// Remembers the reading position (called on every page change).
  Future<void> saveProgress(String bookId, int page) async {
    final book = state.bookById(bookId);
    if (book == null) return;
    await updateBook(
      book.copyWith(lastPage: page, lastOpenedAt: DateTime.now()),
    );
  }

  Future<void> deleteBook(String id) async {
    final book = state.bookById(id);
    if (book == null) return;
    await _repo.deleteFiles(book);
    await _set(books: state.books.where((b) => b.id != id).toList());
    await ref.read(bookmarksProvider.notifier).removeForBooks({id});
  }

  /// "my_great-book.pdf" → "my great book"
  static String prettifyFileName(String name) {
    var title = name.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '');
    title = title.replaceAll(RegExp(r'[_]+|(?<=\S)-(?=\S)'), ' ');
    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    return title.isEmpty ? tr('Untitled') : title;
  }
}

// ---------------------------------------------------------------------------
// Bookmarks
// ---------------------------------------------------------------------------

final bookmarksProvider = NotifierProvider<BookmarksNotifier, List<Bookmark>>(
  BookmarksNotifier.new,
);

class BookmarksNotifier extends Notifier<List<Bookmark>> {
  BooksRepository get _repo => ref.read(booksRepositoryProvider);

  @override
  List<Bookmark> build() => _repo.getBookmarks();

  Future<void> _set(List<Bookmark> value) async {
    state = value;
    await _repo.saveBookmarks(value);
  }

  /// Adds a bookmark, or removes it if the page is already bookmarked.
  Future<bool> toggle(String bookId, int page) async {
    final existing = state.where((b) => b.bookId == bookId && b.page == page);
    if (existing.isNotEmpty) {
      await _set(state.where((b) => !existing.contains(b)).toList());
      return false;
    }
    await _set([
      ...state,
      Bookmark(
        id: _uuid.v4(),
        bookId: bookId,
        page: page,
        createdAt: DateTime.now(),
      ),
    ]);
    return true;
  }

  Future<void> updateNote(String id, String note) => _set([
    for (final b in state) b.id == id ? b.copyWith(note: note.trim()) : b,
  ]);

  Future<void> remove(String id) =>
      _set(state.where((b) => b.id != id).toList());

  Future<void> removeForBooks(Set<String> bookIds) =>
      _set(state.where((b) => !bookIds.contains(b.bookId)).toList());
}

/// Bookmarks of one book, by page.
final bookBookmarksProvider = Provider.family<List<Bookmark>, String>((
  ref,
  bookId,
) {
  return ref.watch(bookmarksProvider).where((b) => b.bookId == bookId).toList()
    ..sort((a, b) => a.page.compareTo(b.page));
});

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

final readerSettingsProvider =
    NotifierProvider<ReaderSettingsNotifier, ReaderSettings>(
      ReaderSettingsNotifier.new,
    );

class ReaderSettingsNotifier extends Notifier<ReaderSettings> {
  @override
  ReaderSettings build() => ref.read(booksRepositoryProvider).getSettings();

  void update(ReaderSettings Function(ReaderSettings s) change) {
    state = change(state);
    ref.read(booksRepositoryProvider).saveSettings(state);
  }
}

// ---------------------------------------------------------------------------
// Library views
// ---------------------------------------------------------------------------

/// Selected shelf chip on the library screen (`null` = all books).
final selectedShelfProvider = NotifierProvider<SelectedShelfNotifier, String?>(
  SelectedShelfNotifier.new,
);

class SelectedShelfNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}

typedef BookQuery = ({String? shelfId, String search});

final filteredBooksProvider = Provider.family<List<Book>, BookQuery>((
  ref,
  query,
) {
  final library = ref.watch(booksLibraryProvider);
  final sort = ref.watch(readerSettingsProvider.select((s) => s.sort));
  final needle = query.search.trim().toLowerCase();

  final books = library.books.where((b) {
    if (query.shelfId != null && b.shelfId != query.shelfId) return false;
    return needle.isEmpty || b.title.toLowerCase().contains(needle);
  }).toList();

  switch (sort) {
    case BookSort.title:
      books.sort((a, b) => naturalCompare(a.title, b.title));
    case BookSort.recentlyRead:
      books.sort((a, b) {
        final da = a.lastOpenedAt, db = b.lastOpenedAt;
        if (da == null && db == null) return naturalCompare(a.title, b.title);
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });
    case BookSort.recentlyAdded:
      books.sort((a, b) => b.addedAt.compareTo(a.addedAt));
  }
  return books;
});

/// Started books, most recently opened first.
final continueReadingProvider = Provider<List<Book>>((ref) {
  final books = ref
      .watch(booksLibraryProvider)
      .books
      .where((b) => b.isStarted)
      .toList();
  books.sort((a, b) => b.lastOpenedAt!.compareTo(a.lastOpenedAt!));
  return books.take(10).toList();
});

// ---------------------------------------------------------------------------
// Reader
// ---------------------------------------------------------------------------

/// The open PDF for a book; closed automatically when the reader goes away.
final bookDocumentProvider = FutureProvider.autoDispose
    .family<PdfDocument, String>((ref, bookId) async {
      final book = ref.read(booksLibraryProvider).bookById(bookId);
      if (book == null) throw StateError(tr('Book not found'));
      final path = ref
          .read(booksRepositoryProvider)
          .absolutePath(book.fileName);
      final document = await PdfDocument.openFile(path);
      ref.onDispose(document.dispose);
      return document;
    });
