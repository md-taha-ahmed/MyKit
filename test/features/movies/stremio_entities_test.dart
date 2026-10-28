import 'package:flutter_test/flutter_test.dart';
import 'package:mykit/features/movies/data/datasources/stremio_addon_client.dart';
import 'package:mykit/features/movies/domain/entities/stremio_entities.dart';

void main() {
  group('AddonManifest', () {
    final torrentio = AddonManifest.fromJson('https://torrentio.strem.fun', {
      'id': 'com.stremio.torrentio.addon',
      'name': 'Torrentio',
      'catalogs': [],
      'resources': [
        {
          'name': 'stream',
          'types': ['movie', 'series', 'anime'],
          'idPrefixes': ['tt', 'kitsu'],
        },
      ],
      'types': ['movie', 'series', 'anime', 'other'],
      'behaviorHints': {'configurable': true},
    });

    test('matches resources by type and id prefix', () {
      expect(torrentio.supports('stream', 'movie', 'tt0111161'), isTrue);
      expect(torrentio.supports('stream', 'series', 'tt0903747:1:2'), isTrue);
      expect(torrentio.supports('stream', 'movie', 'yt_abc'), isFalse);
      expect(torrentio.supports('subtitles', 'movie', 'tt0111161'), isFalse);
      expect(torrentio.configurable, isTrue);
    });

    test('short resource names use the manifest types and prefixes', () {
      final subs = AddonManifest.fromJson('https://subs.example', {
        'id': 'subs',
        'name': 'Subs',
        'resources': ['subtitles'],
        'types': ['movie', 'series'],
        'idPrefixes': ['tt'],
      });
      expect(subs.supports('subtitles', 'series', 'tt1:1:1'), isTrue);
      expect(subs.supports('subtitles', 'anime', 'tt1'), isFalse);
    });

    test('catalog extras decide browsable and searchable', () {
      final cinemeta = AddonManifest.fromJson('https://v3-cinemeta.strem.io', {
        'id': 'com.linvo.cinemeta',
        'name': 'Cinemeta',
        'resources': ['catalog', 'meta'],
        'types': ['movie', 'series'],
        'catalogs': [
          {
            'type': 'movie',
            'id': 'top',
            'name': 'Popular',
            'extraSupported': ['search', 'genre', 'skip'],
          },
          {
            'type': 'movie',
            'id': 'year',
            'name': 'New',
            'extraSupported': ['genre', 'skip'],
            'extraRequired': ['genre'],
          },
        ],
      });
      final top = cinemeta.catalogs.first;
      final year = cinemeta.catalogs.last;
      expect(top.searchable && top.browsable, isTrue);
      expect(year.browsable, isFalse);
    });
  });

  group('StreamSource', () {
    final source = StreamSource.fromJson('Torrentio', {
      'name': 'Torrentio\n4k HDR',
      'title': 'The.Movie.2160p.BluRay\n👤 190 💾 6.91 GB ⚙️ YTS\n🇬🇧 / 🇷🇺',
      'infoHash': 'C3DA9A3DC2CE14D0D4FC0E87D1B2023502F8DCD6',
      'fileIdx': 0,
      'sources': ['tracker:udp://tracker.example:1337/announce', 'dht:abc'],
      'behaviorHints': {'filename': 'The.Movie.mkv'},
    });

    test('parses Torrentio stats', () {
      expect(source.quality, '4k HDR');
      expect(source.seeders, 190);
      expect(source.size, '6.91 GB');
      expect(source.provider, 'YTS');
      expect(source.resolution, '4K');
      expect(source.release, 'The.Movie.2160p.BluRay\n🇬🇧 / 🇷🇺');
    });

    test('torrent fields', () {
      expect(source.isTorrent, isTrue);
      expect(source.infoHash, 'c3da9a3dc2ce14d0d4fc0e87d1b2023502f8dcd6');
      expect(source.trackers, ['udp://tracker.example:1337/announce']);
      expect(source.filename, 'The.Movie.mkv');
    });

    test('quality falls back to the resolution', () {
      final plain = StreamSource.fromJson('Torrentio', {
        'name': 'Torrentio',
        'title': 'Sintel 720p',
        'infoHash': 'abc',
      });
      expect(plain.quality, '720p');
    });
  });

  test('Episode codes and season order', () {
    final meta = MetaDetail.fromJson({
      'id': 'tt1',
      'type': 'series',
      'name': 'Show',
      'videos': [
        {'id': 'tt1:2:1', 'season': 2, 'episode': 1, 'name': 'B'},
        {'id': 'tt1:0:1', 'season': 0, 'episode': 1, 'name': 'Special'},
        {'id': 'tt1:1:2', 'season': 1, 'episode': 2, 'name': 'A2'},
        {'id': 'tt1:1:1', 'season': 1, 'episode': 1, 'name': 'A1'},
      ],
    });
    expect(meta.seasons, [1, 2, 0]);
    expect(meta.episodes.first.code, 'S01E01');
  });

  test('normalizes add-on install links', () {
    const manifest = 'https://torrentio.strem.fun/manifest.json';
    expect(
      StremioAddonClient.normalizeManifestUrl(
        'stremio://torrentio.strem.fun/manifest.json',
      ),
      manifest,
    );
    expect(
      StremioAddonClient.normalizeManifestUrl('torrentio.strem.fun/'),
      manifest,
    );
    expect(StremioAddonClient.normalizeManifestUrl(manifest), manifest);
  });
}
