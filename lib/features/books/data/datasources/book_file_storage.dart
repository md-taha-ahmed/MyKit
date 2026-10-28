import 'dart:io';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

import '../../domain/repositories/books_repository.dart';

/// Stores PDFs and their cover images under `<documents>/books/`.
class BookFileStorage {
  BookFileStorage(this._documents);

  final Directory _documents;

  static const _booksDir = 'books';
  static const _coversDir = 'books/covers';
  static const _coverWidth = 360;

  String absolutePath(String relative) => '${_documents.path}/$relative';

  Future<ImportedPdf> import(String sourcePath, String bookId) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const BookImportException('The selected file could not be read.');
    }

    final pdfRelative = '$_booksDir/$bookId.pdf';
    final pdfFile = File(absolutePath(pdfRelative));
    await pdfFile.parent.create(recursive: true);
    await source.copy(pdfFile.path);

    try {
      final document = await PdfDocument.openFile(pdfFile.path);
      try {
        if (document.pages.isEmpty) {
          throw const BookImportException('This PDF has no pages.');
        }
        final cover = await _renderCover(document.pages.first, bookId);
        return ImportedPdf(
          fileName: pdfRelative,
          coverFileName: cover,
          pageCount: document.pages.length,
          fileSize: await pdfFile.length(),
        );
      } finally {
        await document.dispose();
      }
    } on BookImportException {
      await _deleteQuietly(pdfFile);
      rethrow;
    } catch (e) {
      await _deleteQuietly(pdfFile);
      throw const BookImportException(
        'Not a readable PDF (it may be damaged or password-protected).',
      );
    }
  }

  /// Renders page 1 to a PNG. Returns its relative path, or null on failure.
  Future<String?> _renderCover(PdfPage page, String bookId) async {
    try {
      final width = _coverWidth;
      final height = (width * page.height / page.width).round();
      final image = await page.render(
        width: width,
        height: height,
        fullWidth: width.toDouble(),
        fullHeight: height.toDouble(),
        backgroundColor: 0xFFFFFFFF,
      );
      if (image == null) return null;
      try {
        final uiImage = await image.createImage();
        final png = await uiImage.toByteData(format: ui.ImageByteFormat.png);
        uiImage.dispose();
        if (png == null) return null;

        final relative = '$_coversDir/$bookId.png';
        final file = File(absolutePath(relative));
        await file.parent.create(recursive: true);
        await file.writeAsBytes(png.buffer.asUint8List());
        return relative;
      } finally {
        image.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  Future<void> delete(String relative) =>
      _deleteQuietly(File(absolutePath(relative)));

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
