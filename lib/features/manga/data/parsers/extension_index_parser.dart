import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../../core/i18n/i18n.dart';
import '../../domain/entities/manga_entities.dart';

/// Minimal protobuf wire-format reader (varint, 64-bit, length-delimited, 32-bit).
class _ProtoReader {
  _ProtoReader(this._b);

  final Uint8List _b;
  int _i = 0;

  bool get hasMore => _i < _b.length;

  int varint() {
    var result = 0;
    var shift = 0;
    while (true) {
      final byte = _b[_i++];
      result |= (byte & 0x7f) << shift;
      if (byte < 0x80) return result;
      shift += 7;
    }
  }

  /// Yields (field number, value). Value is int (varint) or Uint8List.
  Iterable<(int, Object)> fields() sync* {
    while (hasMore) {
      final key = varint();
      final field = key >> 3;
      switch (key & 7) {
        case 0:
          yield (field, varint());
        case 1:
          _i += 8;
        case 2:
          final len = varint();
          yield (field, Uint8List.sublistView(_b, _i, _i + len));
          _i += len;
        case 5:
          _i += 4;
        default:
          throw FormatException(tr('Unsupported protobuf wire type'));
      }
    }
  }
}

String _str(Object v) => utf8.decode(v as Uint8List, allowMalformed: true);

/// Parses Mihon repository indexes in every format Mihon accepts.
abstract final class ExtensionIndexParser {
  static Uint8List maybeGunzip(Uint8List bytes) =>
      bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b
      ? Uint8List.fromList(gzip.decode(bytes))
      : bytes;

  /// `repo.json`: `{index_v2, meta: {name, website, signingKeyFingerprint}}`.
  static ({String? indexV2, ExtensionRepo repo}) parseRepoJson(
    String url,
    Map<String, dynamic> json,
  ) {
    final meta = json['meta'] as Map<String, dynamic>;
    return (
      indexV2: json['index_v2'] as String?,
      repo: ExtensionRepo(
        url: url,
        name: meta['name'] as String,
        signingKey: (meta['signingKeyFingerprint'] as String).toLowerCase(),
        website: meta['website'] as String?,
      ),
    );
  }

  /// Protobuf `NetworkExtensionStore`: name(1) badge(2) signingKey(3)
  /// contact(4){website(1)} extensionList(101){extensions(1)} extensionListUrl(102).
  static ({ExtensionRepo repo, Uint8List? list, String? listUrl}) parseStore(
    String url,
    Uint8List bytes,
  ) {
    String name = '', key = '';
    String? website, listUrl;
    Uint8List? list;
    for (final (f, v) in _ProtoReader(bytes).fields()) {
      switch (f) {
        case 1:
          name = _str(v);
        case 3:
          key = _str(v).toLowerCase();
        case 4:
          for (final (cf, cv) in _ProtoReader(v as Uint8List).fields()) {
            if (cf == 1) website = _str(cv);
          }
        case 101:
          list = v as Uint8List;
        case 102:
          listUrl = _str(v);
      }
    }
    return (
      repo: ExtensionRepo(
        url: url,
        name: name,
        signingKey: key,
        website: website,
      ),
      list: list,
      listUrl: listUrl,
    );
  }

  /// Protobuf `ExtensionList { repeated Extension extensions = 1; }`.
  static List<AvailableExtension> parseExtensionList(
    Uint8List bytes,
    ExtensionRepo repo,
  ) => [
    for (final (f, v) in _ProtoReader(bytes).fields())
      if (f == 1) _extension(v as Uint8List, repo),
  ];

  static AvailableExtension _extension(Uint8List bytes, ExtensionRepo repo) {
    var name = '', pkg = '', apk = '', icon = '', lib = '', versionName = '';
    var versionCode = 0, warning = 0;
    var torrent = false;
    final sources = <AvailableSource>[];
    for (final (f, v) in _ProtoReader(bytes).fields()) {
      switch (f) {
        case 1:
          name = _str(v);
        case 2:
          pkg = _str(v);
        case 3:
          for (final (rf, rv) in _ProtoReader(v as Uint8List).fields()) {
            if (rf == 1) apk = _str(rv);
            if (rf == 2) icon = _str(rv);
          }
        case 4:
          lib = _str(v);
        case 5:
          versionCode = v as int;
        case 6:
          versionName = _str(v);
        case 7:
          warning = v as int;
        // Mihon: 8 = sources. Aniyomi (anime): 8 = isTorrent, 9 = sources.
        case 8 when v is Uint8List:
          sources.add(_source(v));
        case 8:
          torrent = v == 1;
        case 9:
          sources.add(_source(v as Uint8List));
      }
    }
    return AvailableExtension(
      name: name,
      pkgName: pkg,
      apkUrl: apk,
      iconUrl: icon,
      libVersion: lib,
      versionCode: versionCode,
      versionName: versionName,
      contentWarning: ContentWarning.values[warning.clamp(0, 3)],
      isTorrent: torrent,
      sources: sources,
      repo: repo,
    );
  }

  static AvailableSource _source(Uint8List bytes) {
    var id = '', name = '', lang = '', home = '';
    for (final (f, v) in _ProtoReader(bytes).fields()) {
      switch (f) {
        // Source ids are signed 64-bit; Dart ints hold them exactly.
        case 1:
          id = '${(v as int).toSigned(64)}';
        case 2:
          name = _str(v);
        case 3:
          lang = _str(v);
        case 4:
          home = _str(v);
      }
    }
    return AvailableSource(id: id, name: name, lang: lang, homeUrl: home);
  }

  /// Legacy `index.min.json` array (pre-0.20 repos).
  static List<AvailableExtension> parseLegacyIndex(
    List<dynamic> json,
    ExtensionRepo repo,
    String baseUrl,
  ) => [
    for (final e in json.cast<Map<String, dynamic>>())
      AvailableExtension(
        name: (e['name'] as String).replaceFirst(
          RegExp(r'^(Tachiyomi|Aniyomi): '),
          '',
        ),
        pkgName: e['pkg'] as String,
        apkUrl: '$baseUrl/apk/${e['apk']}',
        iconUrl: '$baseUrl/icon/${e['pkg']}.png',
        libVersion: (e['version'] as String).substring(
          0,
          (e['version'] as String).lastIndexOf('.'),
        ),
        versionCode: (e['code'] as num).toInt(),
        versionName: e['version'] as String,
        contentWarning: (e['nsfw'] as num?) == 1
            ? ContentWarning.nsfw
            : ContentWarning.safe,
        isTorrent: (e['torrent'] as num?) == 1,
        sources: [
          for (final s
              in (e['sources'] as List? ?? const [])
                  .cast<Map<String, dynamic>>())
            AvailableSource(
              id: '${s['id']}',
              name: s['name'] as String,
              lang: s['lang'] as String,
              homeUrl: s['baseUrl'] as String? ?? '',
            ),
        ],
        repo: repo,
      ),
  ];
}
