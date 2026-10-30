import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Article texts and images saved for reading without a connection, as
/// files under `<documents>/rss_offline/` (one per article / image, named by
/// a hash of the article id or image URL).
class OfflineArticleStore {
  OfflineArticleStore(Directory documents)
    : _dir = Directory('${documents.path}/rss_offline');

  final Directory _dir;

  /// Names of saved images, read once (images are looked up on every build
  /// of a list, so avoid touching the disk each time).
  Set<String>? _imageNames;

  Set<String> get _savedImages => _imageNames ??= {
    if (_images.existsSync())
      for (final f in _images.listSync())
        if (f is File) f.uri.pathSegments.last,
  };

  Directory get _texts => Directory('${_dir.path}/texts');
  Directory get _images => Directory('${_dir.path}/images');

  static String _name(String key) => sha1.convert(utf8.encode(key)).toString();

  File _textFile(String articleId) =>
      File('${_texts.path}/${_name(articleId)}.txt');
  File _imageFile(String url) => File('${_images.path}/${_name(url)}');

  Future<String?> text(String articleId) async {
    final f = _textFile(articleId);
    return await f.exists() ? f.readAsString() : null;
  }

  bool hasText(String articleId) => _textFile(articleId).existsSync();

  Future<void> saveText(String articleId, String text) async {
    await _texts.create(recursive: true);
    await _textFile(articleId).writeAsString(text);
  }

  /// The saved copy of an image, if there is one.
  File? image(String url) =>
      _savedImages.contains(_name(url)) ? _imageFile(url) : null;

  Future<void> saveImage(String url, List<int> bytes) async {
    await _images.create(recursive: true);
    await _imageFile(url).writeAsBytes(bytes);
    _savedImages.add(_name(url));
  }

  /// Deletes copies of articles (and images) that aren't in [keepIds] /
  /// [keepImages] any more.
  Future<void> prune({
    required Set<String> keepIds,
    required Set<String> keepImages,
  }) async {
    final texts = {for (final id in keepIds) '${_name(id)}.txt'};
    final images = {for (final url in keepImages) _name(url)};
    for (final (dir, keep) in [(_texts, texts), (_images, images)]) {
      if (!await dir.exists()) continue;
      await for (final f in dir.list()) {
        final name = f.uri.pathSegments.last;
        if (f is File && !keep.contains(name)) {
          await f.delete();
          _imageNames?.remove(name);
        }
      }
    }
  }

  /// Articles saved and bytes used.
  Future<({int articles, int bytes})> usage() async {
    var articles = 0, bytes = 0;
    for (final dir in [_texts, _images]) {
      if (!await dir.exists()) continue;
      await for (final f in dir.list()) {
        if (f is! File) continue;
        bytes += await f.length();
        if (dir == _texts) articles++;
      }
    }
    return (articles: articles, bytes: bytes);
  }

  Future<void> clear() async {
    if (await _dir.exists()) await _dir.delete(recursive: true);
    _imageNames = {};
  }
}
