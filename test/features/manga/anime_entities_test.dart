import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mykit/features/manga/data/parsers/extension_index_parser.dart';
import 'package:mykit/features/manga/domain/entities/anime_entities.dart';
import 'package:mykit/features/manga/domain/entities/manga_entities.dart';
import 'package:mykit/features/movies/domain/entities/stremio_entities.dart';

/// Minimal protobuf writer for building test stores.
class _Pb {
  final _b = BytesBuilder();

  void _varint(int v) {
    var x = v;
    while (x >= 0x80) {
      _b.addByte((x & 0x7f) | 0x80);
      x >>= 7;
    }
    _b.addByte(x);
  }

  _Pb int_(int field, int v) {
    _varint(field << 3);
    _varint(v);
    return this;
  }

  _Pb bytes(int field, List<int> v) {
    _varint(field << 3 | 2);
    _varint(v.length);
    _b.add(v);
    return this;
  }

  _Pb str(int field, String v) => bytes(field, v.codeUnits);

  Uint8List get done => _b.toBytes();
}

const _repo = ExtensionRepo(url: 'u', name: 'r', signingKey: 'k');

void main() {
  group('extension store protobuf', () {
    List<int> source(int id, String name) =>
        (_Pb()
              ..int_(1, id)
              ..str(2, name)
              ..str(3, 'en'))
            .done;

    test('Mihon manga extension: sources are field 8', () {
      final ext =
          (_Pb()
                ..str(1, 'Tachiyomi: MangaDex')
                ..str(2, 'eu.kanade.tachiyomi.extension.all.mangadex')
                ..str(4, '1.6')
                ..int_(5, 3)
                ..str(6, '1.6.3')
                ..bytes(8, source(1, 'MangaDex')))
              .done;
      final list = ExtensionIndexParser.parseExtensionList(
        (_Pb()..bytes(1, ext)).done,
        _repo,
      );
      expect(list.single.sources.single.name, 'MangaDex');
      expect(list.single.isAnime, isFalse);
      expect(list.single.isSupported, isTrue);
    });

    test('Aniyomi anime extension: 8 = torrent flag, 9 = sources', () {
      final ext =
          (_Pb()
                ..str(1, 'Aniyomi: Nyaa')
                ..str(2, 'eu.kanade.tachiyomi.animeextension.all.nyaa')
                ..str(4, '16')
                ..int_(5, 2)
                ..str(6, '16.2')
                ..int_(7, 2) // mixed content
                ..int_(8, 1) // torrent
                ..bytes(9, source(2, 'Nyaa')))
              .done;
      final e = ExtensionIndexParser.parseExtensionList(
        (_Pb()..bytes(1, ext)).done,
        _repo,
      ).single;
      expect(e.sources.single.name, 'Nyaa');
      expect(e.isAnime, isTrue);
      expect(e.isTorrent, isTrue);
      expect(e.isNsfw, isTrue, reason: 'Aniyomi treats mixed as NSFW');
      expect(
        e.isSupported,
        isFalse,
        reason: 'torrent extensions need TorrServer',
      );
    });
  });

  test('legacy index strips the Aniyomi prefix and reads lib 14', () {
    final list = ExtensionIndexParser.parseLegacyIndex(
      [
        {
          'name': 'Aniyomi: AnimeOnsen',
          'pkg': 'eu.kanade.tachiyomi.animeextension.all.animeonsen',
          'apk': 'a.apk',
          'version': '14.10',
          'code': 10,
          'nsfw': 0,
          'torrent': 0,
          'sources': [
            {'id': 1, 'name': 'AnimeOnsen', 'lang': 'all'},
          ],
        },
      ],
      _repo,
      'https://x',
    );
    expect(list.single.name, 'AnimeOnsen');
    expect(list.single.libVersion, '14');
    expect(list.single.isSupported, isTrue);
  });

  test('Anime map round trip keeps seasons and memo', () {
    final a = Anime.fromMap('42', {
      'url': '/a',
      'title': 'Show',
      'fetchType': 'Seasons',
      'seasonNumber': 2.0,
      'memo': '{"k":1}',
    });
    expect(a.fetchType, AnimeFetchType.seasons);
    final back = Anime.fromMap('42', a.toMap());
    expect(back.fetchType, AnimeFetchType.seasons);
    expect(back.memo, '{"k":1}');
    expect(back.key, 'anime|42|/a');
  });

  test('ResolvedVideo parses headers and tracks', () {
    final v = ResolvedVideo.fromMap({
      'url': 'https://v/master.m3u8',
      'headers': {'Referer': 'https://site/'},
      'subtitles': [
        {'url': 'https://s/en.vtt', 'lang': 'English'},
      ],
    });
    expect(v.headers['Referer'], 'https://site/');
    expect(v.subtitles.single.lang, 'English');
  });

  test('subtitle languages normalise names to codes', () {
    expect(languageCode('eng'), 'eng');
    expect(languageCode('English'), 'eng');
    expect(languageCode('Portuguese (Brazil)'), 'por');
    expect(languageCode('Klingon'), 'Klingon');
  });
}
