import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

import 'hls.dart';

/// The user paused or deleted the download.
class DownloadCancelled implements Exception {
  const DownloadCancelled();
}

/// The server answered with an error status.
class HttpStatusError implements Exception {
  const HttpStatusError(this.code);

  final int code;

  @override
  String toString() => 'HTTP $code';
}

/// A problem retrying won't fix (unsupported video, a web page instead of
/// the file…).
class DownloadFailure implements Exception {
  const DownloadFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Lost or bad connection: worth trying again later by itself.
bool isNetworkError(Object e) =>
    e is SocketException ||
    e is TimeoutException ||
    e is HandshakeException ||
    e is HttpException ||
    e is http.ClientException ||
    (e is HttpStatusError && (e.code >= 500 || e.code == 429 || e.code == 408));

/// Lets a running download be stopped from outside.
class CancelToken {
  bool _cancelled = false;
  final _clients = <http.Client>{};

  bool get cancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    for (final c in _clients) {
      c.close();
    }
    _clients.clear();
  }

  void check() {
    if (_cancelled) throw const DownloadCancelled();
  }
}

typedef DownloadProgress = void Function(double fraction, int bytes);

/// What a video download saved.
class SavedVideo {
  const SavedVideo(this.video, {this.audio});

  final String video;

  /// The sound, when the stream keeps it separate.
  final String? audio;
}

/// Saves videos (single files or HLS streams) and small files, picking up
/// where an interrupted download stopped.
class MediaDownloader {
  MediaDownloader({http.Client Function()? newClient})
    : _newClient = newClient ?? http.Client.new;

  final http.Client Function() _newClient;

  static const _connectTimeout = Duration(seconds: 30);
  static const _stallTimeout = Duration(seconds: 60);
  static const _parallelSegments = 3;

  http.Client _client(CancelToken token) {
    token.check();
    final c = _newClient();
    token._clients.add(c);
    return c;
  }

  void _release(CancelToken token, http.Client c) {
    token._clients.remove(c);
    c.close();
  }

  /// Runs [body] and turns errors caused by a cancel into [DownloadCancelled].
  Future<T> _guard<T>(CancelToken token, Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      if (token.cancelled) throw const DownloadCancelled();
      rethrow;
    }
  }

  // -------------------------------------------------------------------------
  // Videos
  // -------------------------------------------------------------------------

  Future<SavedVideo> downloadVideo({
    required String url,
    required Map<String, String> headers,
    required Directory dir,
    required CancelToken token,
    required DownloadProgress onProgress,
  }) => _guard(token, () async {
    await dir.create(recursive: true);
    final client = _client(token);
    try {
      final hlsState = File('${dir.path}/video.hls');
      if (await hlsState.exists()) {
        final text = await _text(client, Uri.parse(url), headers);
        return await _hls(
          client,
          text,
          Uri.parse(url),
          headers,
          dir,
          token,
          onProgress,
        );
      }
      final part = File('${dir.path}/video.part');
      final have = await part.exists() ? await part.length() : 0;
      final req = http.Request('GET', Uri.parse(url))..headers.addAll(headers);
      if (have > 0) req.headers['Range'] = 'bytes=$have-';
      final res = await client.send(req).timeout(_connectTimeout);
      final type = res.headers['content-type']?.toLowerCase() ?? '';

      if (have > 0 && res.statusCode == 416) {
        // Nothing left to fetch: the file was complete already.
        await res.stream.drain<void>();
        return SavedVideo(await _finish(part, dir, url, type));
      }
      if (res.statusCode != 200 && res.statusCode != 206) {
        await res.stream.drain<void>();
        throw HttpStatusError(res.statusCode);
      }
      if (type.contains('mpegurl') || Uri.parse(url).path.endsWith('.m3u8')) {
        final text = await _readText(res);
        return await _hls(
          client,
          text,
          Uri.parse(url),
          headers,
          dir,
          token,
          onProgress,
        );
      }
      if (type.startsWith('text/html')) {
        await res.stream.drain<void>();
        throw const DownloadFailure(
          'The site sent a web page instead of the video. Try another one.',
        );
      }
      try {
        return SavedVideo(
          await _direct(res, part, have, dir, url, type, token, onProgress),
        );
      } on _ActuallyHls {
        if (await part.exists()) await part.delete();
        final text = await _text(client, Uri.parse(url), headers);
        return await _hls(
          client,
          text,
          Uri.parse(url),
          headers,
          dir,
          token,
          onProgress,
        );
      }
    } finally {
      _release(token, client);
    }
  });

  Future<String> _direct(
    http.StreamedResponse res,
    File part,
    int have,
    Directory dir,
    String url,
    String type,
    CancelToken token,
    DownloadProgress onProgress,
  ) async {
    final append = res.statusCode == 206 && have > 0;
    var bytes = append ? have : 0;
    final int? total;
    if (res.statusCode == 206) {
      final range = res.headers['content-range'] ?? '';
      total =
          int.tryParse(range.split('/').last) ??
          (res.contentLength != null ? bytes + res.contentLength! : null);
    } else {
      total = res.contentLength;
    }

    final sink = part.openWrite(
      mode: append ? FileMode.append : FileMode.write,
    );
    var checkedStart = append;
    var last = DateTime.now();
    try {
      await for (final chunk in res.stream.timeout(_stallTimeout)) {
        token.check();
        if (!checkedStart) {
          checkedStart = true;
          // A playlist served with the wrong type.
          if (chunk.length >= 7 &&
              ascii.decode(chunk.sublist(0, 7), allowInvalid: true) ==
                  '#EXTM3U') {
            throw const _ActuallyHls();
          }
        }
        sink.add(chunk);
        bytes += chunk.length;
        final now = DateTime.now();
        if (now.difference(last) > const Duration(milliseconds: 500)) {
          last = now;
          onProgress(total != null && total > 0 ? bytes / total : 0, bytes);
        }
      }
    } finally {
      await sink.close();
    }
    if (total != null && bytes < total) {
      throw const SocketException('The connection closed early.');
    }
    onProgress(1, bytes);
    return _finish(part, dir, url, type);
  }

  /// Renames `video.part` to `video.<ext>`.
  Future<String> _finish(
    File part,
    Directory dir,
    String url,
    String type,
  ) async {
    final target = File('${dir.path}/video.${_extension(url, type)}');
    if (await target.exists()) await target.delete();
    await part.rename(target.path);
    return target.path;
  }

  static String _extension(String url, String type) {
    if (type.contains('matroska')) return 'mkv';
    if (type.contains('webm')) return 'webm';
    if (type.contains('mp2t')) return 'ts';
    if (type.contains('mp4')) return 'mp4';
    final ext = Uri.parse(url).path.split('.').last.toLowerCase();
    const known = {'mp4', 'mkv', 'webm', 'avi', 'mov', 'm4v', 'ts'};
    return known.contains(ext) ? ext : 'mp4';
  }

  // -------------------------------------------------------------------------
  // HLS
  // -------------------------------------------------------------------------

  Future<SavedVideo> _hls(
    http.Client client,
    String text,
    Uri uri,
    Map<String, String> headers,
    Directory dir,
    CancelToken token,
    DownloadProgress onProgress,
  ) async {
    if (!isHlsPlaylist(text)) {
      throw const DownloadFailure('This video can\'t be downloaded.');
    }
    // Mark it as HLS, so a resumed download goes straight here.
    final marker = File('${dir.path}/video.hls');
    if (!await marker.exists()) await marker.writeAsString('{}');

    var mediaText = text;
    var mediaUri = uri;
    HlsAudio? audio;
    if (isMasterPlaylist(text)) {
      final master = parseMaster(text, uri);
      final variant = master.best;
      audio = master.audioFor(variant);
      mediaUri = variant.uri;
      mediaText = await _text(client, mediaUri, headers);
    }
    final media = parseMedia(mediaText, mediaUri);
    final audioMedia = audio == null
        ? null
        : parseMedia(await _text(client, audio.uri, headers), audio.uri);

    final total = media.segments.length + (audioMedia?.segments.length ?? 0);
    var doneBefore = 0;
    var bytesBefore = 0;
    void report(int done, int bytes) =>
        onProgress((doneBefore + done) / total, bytesBefore + bytes);

    final keys = <Uri, Uint8List>{};
    final video = File(
      '${dir.path}/video.${media.isFragmentedMp4 ? 'mp4' : 'ts'}',
    );
    final videoBytes = await _saveMedia(
      client,
      media,
      headers,
      video,
      File('${dir.path}/video.state'),
      keys,
      token,
      report,
    );
    String? audioPath;
    if (audioMedia != null) {
      doneBefore = media.segments.length;
      bytesBefore = videoBytes;
      final first = audioMedia.segments.first.uri.path.toLowerCase();
      final ext = audioMedia.isFragmentedMp4
          ? 'm4a'
          : first.endsWith('.aac')
          ? 'aac'
          : 'ts';
      final file = File('${dir.path}/audio.$ext');
      await _saveMedia(
        client,
        audioMedia,
        headers,
        file,
        File('${dir.path}/audio.state'),
        keys,
        token,
        report,
      );
      audioPath = file.path;
    }
    return SavedVideo(video.path, audio: audioPath);
  }

  /// Appends the segments to [out] in order, a few fetched at a time.
  /// [stateFile] remembers how far it got, so a restart continues there.
  Future<int> _saveMedia(
    http.Client client,
    HlsMedia media,
    Map<String, String> headers,
    File out,
    File stateFile,
    Map<Uri, Uint8List> keys,
    CancelToken token,
    void Function(int done, int bytes) report,
  ) async {
    var state = <String, dynamic>{};
    if (await stateFile.exists()) {
      try {
        state =
            jsonDecode(await stateFile.readAsString()) as Map<String, dynamic>;
      } catch (_) {}
    }
    var done = (state['done'] as num?)?.toInt() ?? 0;
    var bytes = (state['bytes'] as num?)?.toInt() ?? 0;
    var hasInit = state['init'] == true;
    final n = media.segments.length;
    if (state['complete'] == true && await out.exists()) {
      report(n, bytes);
      return bytes;
    }
    // A different playlist than before (new link): start over.
    if (state['segments'] != null && state['segments'] != n) {
      done = 0;
      bytes = 0;
      hasInit = false;
    }

    final file = await out.open(mode: FileMode.append);
    try {
      await file.truncate(bytes);
      await file.setPosition(bytes);
      Future<void> save({bool complete = false}) => stateFile.writeAsString(
        jsonEncode({
          'done': done,
          'bytes': bytes,
          'init': hasInit,
          'segments': n,
          'complete': complete,
        }),
      );

      if (media.initUri != null && !hasInit) {
        final init = await _bytes(client, media.initUri!, headers);
        await file.writeFrom(init);
        bytes += init.length;
        hasInit = true;
        await save();
      }

      final pending = <int, Future<Uint8List>>{};
      var launched = done;
      while (done < n) {
        token.check();
        while (pending.length < _parallelSegments && launched < n) {
          final seg = media.segments[launched];
          pending[launched] = _segment(client, seg, headers, keys)..ignore();
          launched++;
        }
        final data = await pending.remove(done)!;
        await file.writeFrom(data);
        bytes += data.length;
        done++;
        await save();
        report(done, bytes);
      }
      await save(complete: true);
      return bytes;
    } finally {
      await file.close();
    }
  }

  Future<Uint8List> _segment(
    http.Client client,
    HlsSegment seg,
    Map<String, String> headers,
    Map<Uri, Uint8List> keys,
  ) async {
    // A dropped segment is retried here a few times before giving up.
    for (var attempt = 1; ; attempt++) {
      try {
        final data = await _bytes(client, seg.uri, headers);
        final key = seg.key;
        if (key == null) return data;
        final k = keys[key.uri] ??= await _bytes(client, key.uri, headers);
        final clear = await AesCbc.with128bits(macAlgorithm: MacAlgorithm.empty)
            .decrypt(
              SecretBox(data, nonce: seg.iv, mac: Mac.empty),
              secretKey: SecretKey(k),
            );
        return Uint8List.fromList(clear);
      } catch (e) {
        if (attempt >= 3 || !isNetworkError(e)) rethrow;
        await Future<void>.delayed(Duration(seconds: 2 * attempt));
      }
    }
  }

  // -------------------------------------------------------------------------
  // Small files
  // -------------------------------------------------------------------------

  /// Saves a small file (subtitle, cover, page) in one go.
  Future<File> downloadSmall({
    required String url,
    required Map<String, String> headers,
    required File target,
    required CancelToken token,
  }) => _guard(token, () async {
    final client = _client(token);
    try {
      final data = await _bytes(client, Uri.parse(url), headers);
      await target.parent.create(recursive: true);
      await target.writeAsBytes(data);
      return target;
    } finally {
      _release(token, client);
    }
  });

  Future<Uint8List> _bytes(
    http.Client client,
    Uri uri,
    Map<String, String> headers,
  ) async {
    final res = await client.get(uri, headers: headers).timeout(_stallTimeout);
    if (res.statusCode != 200) throw HttpStatusError(res.statusCode);
    return res.bodyBytes;
  }

  Future<String> _text(
    http.Client client,
    Uri uri,
    Map<String, String> headers,
  ) async =>
      utf8.decode(await _bytes(client, uri, headers), allowMalformed: true);

  Future<String> _readText(http.StreamedResponse res) async => utf8.decode(
    await res.stream.toBytes().timeout(_stallTimeout),
    allowMalformed: true,
  );
}

class _ActuallyHls implements Exception {
  const _ActuallyHls();
}
