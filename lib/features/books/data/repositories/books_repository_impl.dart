import '../../domain/entities/book.dart';
import '../../domain/repositories/books_repository.dart';
import '../datasources/book_file_storage.dart';
import '../datasources/books_local_data_source.dart';

class BooksRepositoryImpl implements BooksRepository {
  BooksRepositoryImpl(this._local, this._files);

  final BooksLocalDataSource _local;
  final BookFileStorage _files;

  @override
  List<BookShelf> getShelves() => _local.readShelves();

  @override
  Future<void> saveShelves(List<BookShelf> shelves) =>
      _local.writeShelves(shelves);

  @override
  List<Book> getBooks() => _local.readBooks();

  @override
  Future<void> saveBooks(List<Book> books) => _local.writeBooks(books);

  @override
  List<Bookmark> getBookmarks() => _local.readBookmarks();

  @override
  Future<void> saveBookmarks(List<Bookmark> bookmarks) =>
      _local.writeBookmarks(bookmarks);

  @override
  ReaderSettings getSettings() => _local.readSettings();

  @override
  Future<void> saveSettings(ReaderSettings settings) =>
      _local.writeSettings(settings);

  @override
  Future<ImportedPdf> importPdf(String sourcePath, String bookId) =>
      _files.import(sourcePath, bookId);

  @override
  Future<void> deleteFiles(Book book) async {
    await _files.delete(book.fileName);
    if (book.coverFileName != null) await _files.delete(book.coverFileName!);
  }

  @override
  String absolutePath(String relativePath) => _files.absolutePath(relativePath);
}
