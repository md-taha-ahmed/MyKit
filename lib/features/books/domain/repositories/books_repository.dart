import '../entities/book.dart';

/// Result of copying a PDF into the library.
class ImportedPdf {
  const ImportedPdf({
    required this.fileName,
    required this.pageCount,
    required this.fileSize,
    this.coverFileName,
  });

  final String fileName;
  final String? coverFileName;
  final int pageCount;
  final int fileSize;
}

class BookImportException implements Exception {
  const BookImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class BooksRepository {
  List<BookShelf> getShelves();
  Future<void> saveShelves(List<BookShelf> shelves);

  List<Book> getBooks();
  Future<void> saveBooks(List<Book> books);

  List<Bookmark> getBookmarks();
  Future<void> saveBookmarks(List<Bookmark> bookmarks);

  ReaderSettings getSettings();
  Future<void> saveSettings(ReaderSettings settings);

  /// Copies the PDF at [sourcePath] into app storage as [bookId], renders a
  /// cover and counts pages.
  Future<ImportedPdf> importPdf(String sourcePath, String bookId);

  /// Removes a book's PDF and cover from storage.
  Future<void> deleteFiles(Book book);

  /// Absolute path for a stored relative path.
  String absolutePath(String relativePath);
}
