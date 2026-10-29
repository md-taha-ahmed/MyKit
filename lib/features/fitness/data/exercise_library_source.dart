import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../domain/entities/fitness_entities.dart';

class FitnessException implements Exception {
  const FitnessException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The exercise database: free-exercise-db (public domain, Unlicense,
/// https://github.com/yuhonas/free-exercise-db). The JSON is downloaded once
/// and cached; photos download the first time they're shown and stay cached.
class ExerciseLibrarySource {
  ExerciseLibrarySource(this._client, Directory documents)
    : _dir = Directory('${documents.path}/fitness');

  final http.Client _client;
  final Directory _dir;

  static const _base =
      'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main';
  static const _refreshAfter = Duration(days: 30);

  File get _jsonFile => File('${_dir.path}/exercises.json');
  Directory get _images => Directory('${_dir.path}/images');
  Directory get _custom => Directory('${_dir.path}/custom');

  /// All exercises; cached copy first, refreshed in the background monthly.
  Future<List<Exercise>> load() async {
    final file = _jsonFile;
    if (await file.exists()) {
      final cached = _parse(await file.readAsString());
      final age = DateTime.now().difference(await file.lastModified());
      if (age > _refreshAfter) _download().ignore();
      if (cached.isNotEmpty) return cached;
    }
    return _parse(await _download());
  }

  Future<String> _download() async {
    final http.Response res;
    try {
      res = await _client
          .get(Uri.parse('$_base/dist/exercises.json'))
          .timeout(const Duration(seconds: 60));
    } catch (_) {
      throw const FitnessException(
        'Could not download the exercise library. Check your connection.',
      );
    }
    if (res.statusCode != 200) {
      throw FitnessException('Exercise library error ${res.statusCode}.');
    }
    final body = utf8.decode(res.bodyBytes);
    await _dir.create(recursive: true);
    await _jsonFile.writeAsString(body);
    return body;
  }

  static List<Exercise> _parse(String json) {
    try {
      return [
        for (final e in jsonDecode(json) as List)
          Exercise.fromJson(e as Map<String, dynamic>),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Local file of a database photo, downloading it the first time.
  Future<File> image(String path) async {
    final file = File('${_images.path}/${path.replaceAll('/', '__')}');
    if (await file.exists() && await file.length() > 0) return file;
    final res = await _client
        .get(Uri.parse('$_base/exercises/$path'))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw FitnessException('Image unavailable (${res.statusCode}).');
    }
    await _images.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(res.bodyBytes);
    await tmp.rename(file.path);
    return file;
  }

  /// Copies a user-picked photo into app storage; returns its path.
  Future<String> saveCustomImage(String exerciseId, String sourcePath) async {
    await _custom.create(recursive: true);
    final ext = sourcePath.contains('.')
        ? sourcePath.substring(sourcePath.lastIndexOf('.'))
        : '.jpg';
    final safe = exerciseId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final target = File(
      '${_custom.path}/${safe}_${DateTime.now().millisecondsSinceEpoch}$ext',
    );
    await File(sourcePath).copy(target.path);
    return target.path;
  }

  Future<void> deleteFile(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }
}
