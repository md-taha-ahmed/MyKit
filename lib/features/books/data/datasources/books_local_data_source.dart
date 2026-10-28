import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/book.dart';

/// Library metadata in SharedPreferences (the PDFs themselves live on disk).
class BooksLocalDataSource {
  BooksLocalDataSource(this._prefs);

  static const _shelvesKey = 'books.shelves.v1';
  static const _booksKey = 'books.items.v1';
  static const _bookmarksKey = 'books.bookmarks.v1';
  static const _settingsKey = 'books.settings.v1';

  final SharedPreferences _prefs;

  List<BookShelf> readShelves() => _read(_shelvesKey)
      .map((j) => BookShelf(id: j['id'] as String, name: j['name'] as String))
      .toList();

  Future<void> writeShelves(List<BookShelf> shelves) => _write(_shelvesKey, [
    for (final s in shelves) {'id': s.id, 'name': s.name},
  ]);

  List<Book> readBooks() => _read(_booksKey)
      .map(
        (j) => Book(
          id: j['id'] as String,
          title: j['title'] as String,
          shelfId: j['shelfId'] as String,
          fileName: j['fileName'] as String,
          coverFileName: j['coverFileName'] as String?,
          pageCount: j['pageCount'] as int? ?? 0,
          fileSize: j['fileSize'] as int? ?? 0,
          addedAt: DateTime.parse(j['addedAt'] as String),
          lastPage: j['lastPage'] as int? ?? 1,
          lastOpenedAt: DateTime.tryParse(j['lastOpenedAt'] as String? ?? ''),
        ),
      )
      .toList();

  Future<void> writeBooks(List<Book> books) => _write(_booksKey, [
    for (final b in books)
      {
        'id': b.id,
        'title': b.title,
        'shelfId': b.shelfId,
        'fileName': b.fileName,
        'coverFileName': b.coverFileName,
        'pageCount': b.pageCount,
        'fileSize': b.fileSize,
        'addedAt': b.addedAt.toIso8601String(),
        'lastPage': b.lastPage,
        'lastOpenedAt': b.lastOpenedAt?.toIso8601String(),
      },
  ]);

  List<Bookmark> readBookmarks() => _read(_bookmarksKey)
      .map(
        (j) => Bookmark(
          id: j['id'] as String,
          bookId: j['bookId'] as String,
          page: j['page'] as int,
          note: j['note'] as String? ?? '',
          createdAt: DateTime.parse(j['createdAt'] as String),
        ),
      )
      .toList();

  Future<void> writeBookmarks(List<Bookmark> bookmarks) =>
      _write(_bookmarksKey, [
        for (final b in bookmarks)
          {
            'id': b.id,
            'bookId': b.bookId,
            'page': b.page,
            'note': b.note,
            'createdAt': b.createdAt.toIso8601String(),
          },
      ]);

  ReaderSettings readSettings() {
    final raw = _prefs.getString(_settingsKey);
    if (raw == null) return const ReaderSettings();
    final j = jsonDecode(raw) as Map<String, dynamic>;
    const d = ReaderSettings();
    return ReaderSettings(
      scrollMode:
          ReaderScrollMode.values.asNameMap()[j['scrollMode']] ?? d.scrollMode,
      colorMode:
          ReaderColorMode.values.asNameMap()[j['colorMode']] ?? d.colorMode,
      sort: BookSort.values.asNameMap()[j['sort']] ?? d.sort,
    );
  }

  Future<void> writeSettings(ReaderSettings s) => _prefs.setString(
    _settingsKey,
    jsonEncode({
      'scrollMode': s.scrollMode.name,
      'colorMode': s.colorMode.name,
      'sort': s.sort.name,
    }),
  );

  List<Map<String, dynamic>> _read(String key) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> _write(String key, List<Map<String, dynamic>> value) =>
      _prefs.setString(key, jsonEncode(value));
}
