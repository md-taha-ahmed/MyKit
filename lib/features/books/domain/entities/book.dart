/// A PDF stored in the app's library.
class Book {
  const Book({
    required this.id,
    required this.title,
    required this.shelfId,
    required this.fileName,
    required this.pageCount,
    required this.fileSize,
    required this.addedAt,
    this.coverFileName,
    this.lastPage = 1,
    this.lastOpenedAt,
  });

  final String id;
  final String title;
  final String shelfId;

  /// Path of the PDF relative to the app documents directory.
  final String fileName;

  /// Path of the cover PNG relative to the app documents directory.
  final String? coverFileName;
  final int pageCount;
  final int fileSize;
  final DateTime addedAt;

  /// 1-based page the reader was on last time.
  final int lastPage;
  final DateTime? lastOpenedAt;

  bool get isStarted => lastOpenedAt != null;

  /// 0..1 reading progress.
  double get progress =>
      pageCount <= 0 ? 0 : (lastPage / pageCount).clamp(0.0, 1.0);

  Book copyWith({
    String? title,
    String? shelfId,
    int? lastPage,
    DateTime? lastOpenedAt,
  }) => Book(
    id: id,
    title: title ?? this.title,
    shelfId: shelfId ?? this.shelfId,
    fileName: fileName,
    coverFileName: coverFileName,
    pageCount: pageCount,
    fileSize: fileSize,
    addedAt: addedAt,
    lastPage: lastPage ?? this.lastPage,
    lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
  );
}

/// A category of books.
class BookShelf {
  const BookShelf({required this.id, required this.name});

  final String id;
  final String name;

  BookShelf copyWith({String? name}) =>
      BookShelf(id: id, name: name ?? this.name);
}

class Bookmark {
  const Bookmark({
    required this.id,
    required this.bookId,
    required this.page,
    required this.createdAt,
    this.note = '',
  });

  final String id;
  final String bookId;
  final int page;
  final String note;
  final DateTime createdAt;

  Bookmark copyWith({String? note}) => Bookmark(
    id: id,
    bookId: bookId,
    page: page,
    createdAt: createdAt,
    note: note ?? this.note,
  );
}

enum ReaderScrollMode {
  vertical('Vertical', 'Continuous scroll'),
  horizontal('Horizontal', 'Swipe page by page');

  const ReaderScrollMode(this.label, this.description);
  final String label;
  final String description;
}

enum ReaderColorMode {
  light('Light'),
  dark('Dark'),
  sepia('Sepia');

  const ReaderColorMode(this.label);
  final String label;
}

enum BookSort {
  title('Title (A–Z)'),
  recentlyRead('Recently read'),
  recentlyAdded('Recently added');

  const BookSort(this.label);
  final String label;
}

class ReaderSettings {
  const ReaderSettings({
    this.scrollMode = ReaderScrollMode.vertical,
    this.colorMode = ReaderColorMode.light,
    this.sort = BookSort.title,
  });

  final ReaderScrollMode scrollMode;
  final ReaderColorMode colorMode;

  /// Library sort order.
  final BookSort sort;

  ReaderSettings copyWith({
    ReaderScrollMode? scrollMode,
    ReaderColorMode? colorMode,
    BookSort? sort,
  }) => ReaderSettings(
    scrollMode: scrollMode ?? this.scrollMode,
    colorMode: colorMode ?? this.colorMode,
    sort: sort ?? this.sort,
  );
}
