import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mykit/features/manga/data/parsers/extension_index_parser.dart';
import 'package:mykit/features/manga/domain/entities/manga_entities.dart';

// Tiny protobuf writer for building fixtures.
List<int> _varint(int v) {
  final out = <int>[];
  var x = v;
  while (true) {
    if (x >= 0 && x < 0x80) return out..add(x);
    out.add((x & 0x7f) | 0x80);
    x = x >>> 7;
  }
}

List<int> _str(int field, String s) => _bytes(field, utf8.encode(s));
List<int> _bytes(int field, List<int> b) => [
  ..._varint(field << 3 | 2),
  ..._varint(b.length),
  ...b,
];
List<int> _int(int field, int v) => [..._varint(field << 3), ..._varint(v)];

void main() {
  test('parses a protobuf store with an inline extension list', () {
    final source = [
      ..._int(1, -1234567890123), // negative 64-bit id
      ..._str(2, 'MangaDex'),
      ..._str(3, 'en'),
      ..._str(4, 'https://mangadex.org'),
    ];
    final ext = [
      ..._str(1, 'MangaDex'),
      ..._str(2, 'eu.kanade.tachiyomi.extension.all.mangadex'),
      ..._bytes(3, [
        ..._str(1, 'https://x/md.apk'),
        ..._str(2, 'https://x/md.png'),
      ]),
      ..._str(4, '1.6'),
      ..._int(5, 106000),
      ..._str(6, '1.6.0'),
      ..._int(7, 3),
      ..._bytes(8, source),
    ];
    final store = Uint8List.fromList([
      ..._str(1, 'Test Repo'),
      ..._str(3, 'ABCDEF'),
      ..._bytes(4, _str(1, 'https://example.com')),
      ..._bytes(101, _bytes(1, ext)),
    ]);

    final gz = Uint8List.fromList(gzip.encode(store));
    final parsed = ExtensionIndexParser.parseStore(
      'u',
      ExtensionIndexParser.maybeGunzip(gz),
    );
    expect(parsed.repo.name, 'Test Repo');
    expect(parsed.repo.signingKey, 'abcdef');
    expect(parsed.repo.website, 'https://example.com');

    final list = ExtensionIndexParser.parseExtensionList(
      parsed.list!,
      parsed.repo,
    );
    final e = list.single;
    expect(e.pkgName, 'eu.kanade.tachiyomi.extension.all.mangadex');
    expect(e.apkUrl, 'https://x/md.apk');
    expect(e.versionCode, 106000);
    expect(e.contentWarning, ContentWarning.nsfw);
    expect(e.isSupported, isTrue);
    expect(e.lang, 'en');
    expect(e.sources.single.id, '-1234567890123');
  });
}
