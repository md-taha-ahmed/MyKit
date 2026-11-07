import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykit/features/downloads/data/hls.dart';
import 'package:mykit/features/downloads/data/media_downloader.dart';
import 'package:mykit/features/downloads/domain/download_item.dart';

/// A tiny local web server: path → bytes (+ content type), Range support,
/// and an optional cut after N bytes to imitate a lost connection.
class _Server {
  late HttpServer server;
  final files = <String, (List<int>, String)>{};
  final requests = <String>[];
  int? cutAfter;
  bool slow = false;

  String get base => 'http://127.0.0.1:${server.port}';

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      requests.add('${req.uri.path} ${req.headers.value('range') ?? ''}');
      final file = files[req.uri.path];
      if (file == null) {
        req.response.statusCode = 404;
        await req.response.close();
        return;
      }
      final (bytes, type) = file;
      req.response.headers.contentType = ContentType.parse(type);
      var start = 0;
      final range = req.headers.value('range');
      if (range != null) {
        start = int.parse(range.substring(6).split('-').first);
        if (start >= bytes.length) {
          req.response.statusCode = 416;
          await req.response.close();
          return;
        }
        req.response.statusCode = 206;
        req.response.headers.set(
          'content-range',
          'bytes $start-${bytes.length - 1}/${bytes.length}',
        );
      }
      final body = bytes.sublist(start);
      req.response.contentLength = body.length;
      final cut = cutAfter;
      if (cut != null && body.length > cut) {
        cutAfter = null;
        // Send part of the file, then drop the connection.
        final socket = await req.response.detachSocket();
        socket.add(body.sublist(0, cut));
        await socket.flush();
        socket.destroy();
        return;
      }
      if (slow) {
        for (var i = 0; i < body.length; i += 65536) {
          req.response.add(body.sublist(i, (i + 65536).clamp(0, body.length)));
          await req.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        await req.response.close();
        return;
      }
      req.response.add(body);
      await req.response.close();
    });
  }
}

List<int> _bytes(int n, [int seed = 0]) =>
    List.generate(n, (i) => (i * 7 + seed) % 256);

void main() {
  late _Server s;
  late Directory dir;
  final downloader = MediaDownloader();

  setUp(() async {
    s = _Server();
    await s.start();
    dir = await Directory.systemTemp.createTemp('dl_test');
  });

  tearDown(() async {
    await s.server.close(force: true);
    await dir.delete(recursive: true);
  });

  test('saves a single file with the right extension', () async {
    final data = _bytes(300000);
    s.files['/movie.mkv'] = (data, 'video/x-matroska');
    double last = 0;
    final saved = await downloader.downloadVideo(
      url: '${s.base}/movie.mkv',
      headers: const {},
      dir: dir,
      token: CancelToken(),
      onProgress: (f, _) => last = f,
    );
    expect(saved.video, endsWith('video.mkv'));
    expect(await File(saved.video).readAsBytes(), data);
    expect(last, 1);
  });

  test('continues an interrupted file where it stopped', () async {
    final data = _bytes(400000, 3);
    s.files['/v.mp4'] = (data, 'video/mp4');
    s.cutAfter = 150000;
    Object? error;
    try {
      await downloader.downloadVideo(
        url: '${s.base}/v.mp4',
        headers: const {},
        dir: dir,
        token: CancelToken(),
        onProgress: (_, _) {},
      );
    } catch (e) {
      error = e;
    }
    expect(error, isNotNull);
    expect(isNetworkError(error!), isTrue, reason: '$error');
    final part = File('${dir.path}/video.part');
    expect(await part.exists(), isTrue);
    expect(await part.length(), greaterThan(0));

    final saved = await downloader.downloadVideo(
      url: '${s.base}/v.mp4',
      headers: const {},
      dir: dir,
      token: CancelToken(),
      onProgress: (_, _) {},
    );
    expect(await File(saved.video).readAsBytes(), data);
    expect(s.requests.last, contains('bytes='));
  });

  test('a web page instead of a video is a failure, not a retry', () async {
    s.files['/page'] = ('<html></html>'.codeUnits, 'text/html');
    await expectLater(
      downloader.downloadVideo(
        url: '${s.base}/page',
        headers: const {},
        dir: dir,
        token: CancelToken(),
        onProgress: (_, _) {},
      ),
      throwsA(isA<DownloadFailure>()),
    );
  });

  test('joins HLS segments, decrypting AES-128 ones', () async {
    final key = List<int>.generate(16, (i) => i + 1);
    final aes = AesCbc.with128bits(macAlgorithm: MacAlgorithm.empty);
    final plain = [_bytes(5000, 1), _bytes(4000, 2), _bytes(3000, 3)];
    final enc = <List<int>>[];
    for (var i = 0; i < plain.length; i++) {
      final iv = Uint8List(16)..[15] = i;
      final box = await aes.encrypt(
        plain[i],
        secretKey: SecretKey(key),
        nonce: iv,
      );
      enc.add(box.cipherText);
    }
    s.files['/key.bin'] = (key, 'application/octet-stream');
    for (var i = 0; i < 3; i++) {
      s.files['/hls/s$i.ts'] = (enc[i], 'video/mp2t');
    }
    s.files['/hls/media.m3u8'] = (
      '#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:0\n'
              '#EXT-X-KEY:METHOD=AES-128,URI="/key.bin"\n'
              '#EXTINF:4,\ns0.ts\n#EXTINF:4,\ns1.ts\n#EXTINF:4,\ns2.ts\n'
              '#EXT-X-ENDLIST\n'
          .codeUnits,
      'application/vnd.apple.mpegurl',
    );
    s.files['/master.m3u8'] = (
      '#EXTM3U\n'
              '#EXT-X-STREAM-INF:BANDWIDTH=100,RESOLUTION=320x180\nlow.m3u8\n'
              '#EXT-X-STREAM-INF:BANDWIDTH=900,RESOLUTION=1280x720\nhls/media.m3u8\n'
          .codeUnits,
      'application/x-mpegurl',
    );

    final saved = await downloader.downloadVideo(
      url: '${s.base}/master.m3u8',
      headers: const {},
      dir: dir,
      token: CancelToken(),
      onProgress: (_, _) {},
    );
    expect(saved.video, endsWith('video.ts'));
    expect(await File(saved.video).readAsBytes(), [
      ...plain[0],
      ...plain[1],
      ...plain[2],
    ]);
    expect(s.requests.any((r) => r.startsWith('/low.m3u8')), isFalse);
  });

  test('fMP4 HLS starts with the init part; separate audio is saved', () async {
    s.files['/init.mp4'] = (_bytes(100, 9), 'video/mp4');
    s.files['/v1.m4s'] = (_bytes(2000, 4), 'video/iso.segment');
    s.files['/a1.aac'] = (_bytes(500, 5), 'audio/aac');
    s.files['/v.m3u8'] = (
      '#EXTM3U\n#EXT-X-MAP:URI="init.mp4"\n#EXTINF:4,\nv1.m4s\n'.codeUnits,
      'application/vnd.apple.mpegurl',
    );
    s.files['/a.m3u8'] = (
      '#EXTM3U\n#EXTINF:4,\na1.aac\n'.codeUnits,
      'application/vnd.apple.mpegurl',
    );
    s.files['/m.m3u8'] = (
      '#EXTM3U\n'
              '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="Japanese",LANGUAGE="ja",DEFAULT=YES,URI="a.m3u8"\n'
              '#EXT-X-STREAM-INF:BANDWIDTH=900,AUDIO="aud"\nv.m3u8\n'
          .codeUnits,
      'application/vnd.apple.mpegurl',
    );
    final saved = await downloader.downloadVideo(
      url: '${s.base}/m.m3u8',
      headers: const {},
      dir: dir,
      token: CancelToken(),
      onProgress: (_, _) {},
    );
    expect(saved.video, endsWith('video.mp4'));
    expect(await File(saved.video).readAsBytes(), [
      ..._bytes(100, 9),
      ..._bytes(2000, 4),
    ]);
    expect(saved.audio, endsWith('audio.aac'));
    expect(await File(saved.audio!).readAsBytes(), _bytes(500, 5));
  });

  test('a cancelled download says so', () async {
    s.files['/big.mp4'] = (_bytes(4000000), 'video/mp4');
    s.slow = true;
    final token = CancelToken();
    final future = downloader.downloadVideo(
      url: '${s.base}/big.mp4',
      headers: const {},
      dir: dir,
      token: token,
      onProgress: (_, _) {},
    );
    Timer(const Duration(milliseconds: 400), token.cancel);
    await expectLater(future, throwsA(isA<DownloadCancelled>()));
  });

  group('playlists', () {
    test('picks the best variant and its audio group', () {
      final m = parseMaster(
        '#EXTM3U\n'
        '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",NAME="En",URI="en.m3u8"\n'
        '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",NAME="Ja",DEFAULT=YES,URI="ja.m3u8"\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=640x360,AUDIO="a"\n360.m3u8\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=2,RESOLUTION=1920x1080,AUDIO="a"\n1080.m3u8\n',
        Uri.parse('https://x.test/path/master.m3u8'),
      );
      expect(m.best.uri.toString(), 'https://x.test/path/1080.m3u8');
      expect(m.audioFor(m.best)!.name, 'Ja');
    });

    test('DRM streams are refused with a clear message', () {
      expect(
        () => parseMedia(
          '#EXTM3U\n#EXT-X-KEY:METHOD=SAMPLE-AES,URI="k"\n#EXTINF:4,\na.ts\n',
          Uri.parse('https://x.test/'),
        ),
        throwsA(isA<HlsException>()),
      );
    });

    test('IV defaults to the sequence number', () {
      final seg = HlsSegment(
        uri: Uri.parse('https://x.test/a.ts'),
        sequence: 258,
        key: HlsKey(uri: Uri.parse('https://x.test/k')),
      );
      expect(seg.iv.sublist(14), [1, 2]);
    });
  });

  test('download items survive a save and load', () {
    final item = DownloadItem(
      id: DownloadItem.idFor(DownloadKind.anime, 'anime|1|/a', '/ep1'),
      kind: DownloadKind.anime,
      groupKey: 'anime|1|/a',
      groupTitle: 'Frieren',
      itemKey: '/ep1',
      itemTitle: 'Episode 1',
      order: 1,
      dir: '/tmp/x',
      addedAt: DateTime(2026, 11, 6),
      state: DownloadState.done,
      progress: 1,
      bytes: 1234,
      result: {
        'video': '/tmp/x/video.mp4',
        'subtitles': [
          {'path': '/tmp/x/sub_1.vtt', 'lang': 'English'},
        ],
      },
    );
    final back = DownloadItem.fromJson(
      Map<String, dynamic>.from(item.toJson()),
    );
    expect(back.id, item.id);
    expect(back.state, DownloadState.done);
    expect(back.videoPath, '/tmp/x/video.mp4');
    expect(back.subtitles.single.lang, 'English');
    expect(formatBytes(1536 * 1024 * 1024), '1.5 GB');
  });
}
