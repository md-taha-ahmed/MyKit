/// Just enough of HLS (`.m3u8`) to save a stream as one file.
library;

import 'dart:typed_data';

class HlsVariant {
  const HlsVariant({
    required this.uri,
    this.bandwidth = 0,
    this.height = 0,
    this.audioGroup,
  });

  final Uri uri;
  final int bandwidth;
  final int height;
  final String? audioGroup;
}

/// A separate audio rendition (`#EXT-X-MEDIA:TYPE=AUDIO` with a URI).
class HlsAudio {
  const HlsAudio({
    required this.uri,
    required this.group,
    this.language = '',
    this.name = '',
    this.isDefault = false,
  });

  final Uri uri;
  final String group;
  final String language;
  final String name;
  final bool isDefault;
}

class HlsMaster {
  const HlsMaster(this.variants, this.audios);

  final List<HlsVariant> variants;
  final List<HlsAudio> audios;

  /// Highest quality: the stream was already chosen by quality in the picker,
  /// and a master playlist usually lists just that one.
  HlsVariant get best => variants.reduce(
    (a, b) =>
        b.height > a.height ||
            (b.height == a.height && b.bandwidth > a.bandwidth)
        ? b
        : a,
  );

  /// The audio to save next to [variant], when its sound is separate.
  HlsAudio? audioFor(HlsVariant variant) {
    final group = variant.audioGroup;
    if (group == null) return null;
    final options = audios.where((a) => a.group == group).toList();
    if (options.isEmpty) return null;
    return options.where((a) => a.isDefault).firstOrNull ?? options.first;
  }
}

class HlsKey {
  const HlsKey({required this.uri, this.iv});

  /// AES-128 key location.
  final Uri uri;

  /// Explicit IV; otherwise the segment's media sequence number.
  final Uint8List? iv;
}

class HlsSegment {
  const HlsSegment({required this.uri, required this.sequence, this.key});

  final Uri uri;
  final int sequence;
  final HlsKey? key;

  /// IV for AES-128: the given one, else the sequence number big-endian.
  Uint8List get iv {
    final explicit = key?.iv;
    if (explicit != null) return explicit;
    final iv = Uint8List(16);
    var n = sequence;
    for (var i = 15; i >= 0 && n > 0; i--) {
      iv[i] = n & 0xff;
      n >>= 8;
    }
    return iv;
  }
}

class HlsMedia {
  const HlsMedia(this.segments, {this.initUri});

  final List<HlsSegment> segments;

  /// fMP4 init section (`#EXT-X-MAP`); null for MPEG-TS.
  final Uri? initUri;

  bool get isFragmentedMp4 => initUri != null;
}

class HlsException implements Exception {
  const HlsException(this.message);

  final String message;

  @override
  String toString() => message;
}

bool isHlsPlaylist(String text) => text.trimLeft().startsWith('#EXTM3U');

bool isMasterPlaylist(String text) => text.contains('#EXT-X-STREAM-INF');

HlsMaster parseMaster(String text, Uri base) {
  final variants = <HlsVariant>[];
  final audios = <HlsAudio>[];
  final lines = _lines(text);
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.startsWith('#EXT-X-STREAM-INF:')) {
      final attrs = parseAttributes(line.substring(18));
      final uriLine = lines.skip(i + 1).where((l) => !l.startsWith('#'));
      if (uriLine.isEmpty) continue;
      final res = attrs['RESOLUTION']?.split('x');
      variants.add(
        HlsVariant(
          uri: base.resolve(uriLine.first),
          bandwidth: int.tryParse(attrs['BANDWIDTH'] ?? '') ?? 0,
          height: res != null && res.length == 2
              ? int.tryParse(res[1]) ?? 0
              : 0,
          audioGroup: attrs['AUDIO'],
        ),
      );
    } else if (line.startsWith('#EXT-X-MEDIA:')) {
      final attrs = parseAttributes(line.substring(13));
      final uri = attrs['URI'];
      if (attrs['TYPE'] != 'AUDIO' || uri == null) continue;
      audios.add(
        HlsAudio(
          uri: base.resolve(uri),
          group: attrs['GROUP-ID'] ?? '',
          language: attrs['LANGUAGE'] ?? '',
          name: attrs['NAME'] ?? '',
          isDefault: attrs['DEFAULT'] == 'YES',
        ),
      );
    }
  }
  if (variants.isEmpty) throw const HlsException('Empty HLS playlist.');
  return HlsMaster(variants, audios);
}

HlsMedia parseMedia(String text, Uri base) {
  final segments = <HlsSegment>[];
  Uri? init;
  HlsKey? key;
  var sequence = 0;
  var pendingSegment = false;
  for (final line in _lines(text)) {
    if (line.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
      sequence = int.tryParse(line.substring(22).trim()) ?? 0;
    } else if (line.startsWith('#EXT-X-KEY:')) {
      final attrs = parseAttributes(line.substring(11));
      final method = attrs['METHOD'] ?? 'NONE';
      if (method == 'NONE') {
        key = null;
      } else if (method == 'AES-128' && attrs['URI'] != null) {
        key = HlsKey(uri: base.resolve(attrs['URI']!), iv: _hex(attrs['IV']));
      } else {
        throw HlsException(
          'This video is protected ($method) and can\'t be downloaded.',
        );
      }
    } else if (line.startsWith('#EXT-X-MAP:')) {
      final attrs = parseAttributes(line.substring(11));
      if (attrs.containsKey('BYTERANGE')) {
        throw const HlsException('This kind of stream can\'t be downloaded.');
      }
      if (attrs['URI'] != null) init = base.resolve(attrs['URI']!);
    } else if (line.startsWith('#EXT-X-BYTERANGE')) {
      throw const HlsException('This kind of stream can\'t be downloaded.');
    } else if (line.startsWith('#EXTINF')) {
      pendingSegment = true;
    } else if (!line.startsWith('#') && pendingSegment) {
      segments.add(
        HlsSegment(uri: base.resolve(line), sequence: sequence, key: key),
      );
      sequence++;
      pendingSegment = false;
    }
  }
  if (segments.isEmpty) throw const HlsException('Empty HLS playlist.');
  return HlsMedia(segments, initUri: init);
}

/// `KEY=value,KEY2="quoted, value"`.
Map<String, String> parseAttributes(String s) {
  final out = <String, String>{};
  final re = RegExp(r'([A-Z0-9-]+)=("[^"]*"|[^,]*)');
  for (final m in re.allMatches(s)) {
    var v = m.group(2)!;
    if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
      v = v.substring(1, v.length - 1);
    }
    out[m.group(1)!] = v;
  }
  return out;
}

List<String> _lines(String text) => text
    .split(RegExp(r'\r?\n'))
    .map((l) => l.trim())
    .where((l) => l.isNotEmpty)
    .toList();

Uint8List? _hex(String? s) {
  if (s == null) return null;
  var h = s.toLowerCase();
  if (h.startsWith('0x')) h = h.substring(2);
  h = h.padLeft(32, '0');
  if (h.length != 32) return null;
  return Uint8List.fromList([
    for (var i = 0; i < 32; i += 2) int.parse(h.substring(i, i + 2), radix: 16),
  ]);
}
