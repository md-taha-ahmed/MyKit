import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/entities/stremio_entities.dart';

/// A film or show OpenSubtitles knows, found by name.
class SubtitleTitle {
  const SubtitleTitle({
    required this.imdbId,
    required this.name,
    required this.isSeries,
    this.year,
  });

  final String imdbId;
  final String name;
  final bool isSeries;
  final String? year;

  Map<String, dynamic> toJson() => {
    'id': imdbId,
    'name': name,
    'series': isSeries,
    'year': ?year,
  };

  static SubtitleTitle fromJson(Map<String, dynamic> j) => SubtitleTitle(
    imdbId: j['id'] as String,
    name: j['name'] as String,
    isSeries: j['series'] as bool,
    year: j['year'] as String?,
  );
}

/// What a Stremio video id says: `tt123` or `tt123:1:5`. Null for anything
/// that isn't an IMDb id, which then has to be searched for by name.
({String imdbId, bool isSeries, int? season, int? episode})? parseImdbVideoId(
  String videoId,
) {
  final parts = videoId.split(':');
  if (!parts.first.startsWith('tt')) return null;
  return (
    imdbId: parts.first,
    isSeries: parts.length > 1,
    season: parts.length > 1 ? int.tryParse(parts[1]) : null,
    episode: parts.length > 2 ? int.tryParse(parts[2]) : null,
  );
}

/// The last number in "Episode 12" or "الحلقة 12 - name 2" is not always the
/// episode, so the first one is used; the search lets you correct it.
int? episodeNumberFromLabel(String? label) {
  if (label == null) return null;
  final match = RegExp(r'\d+').firstMatch(label);
  return match == null ? null : int.tryParse(match.group(0)!);
}

/// Searches OpenSubtitles with no account or key, through the same free
/// services Stremio uses: Cinemeta finds the title, OpenSubtitles v3 lists
/// its subtitles. Each is a small JSON request, for low data use.
class OpenSubtitlesClient {
  OpenSubtitlesClient(this._client);

  final http.Client _client;

  static const addonName = 'OpenSubtitles';
  static const _timeout = Duration(seconds: 25);
  static const _catalog = 'https://v3-cinemeta.strem.io/catalog';
  static const _subtitles = 'https://opensubtitles-v3.strem.io/subtitles';

  /// Shows first, or films first, by what's most likely being watched.
  Future<List<SubtitleTitle>> searchTitles(
    String query, {
    bool seriesFirst = true,
  }) async {
    final found = await Future.wait([
      _search('series', query),
      _search('movie', query),
    ]);
    return seriesFirst
        ? [...found[0], ...found[1]]
        : [...found[1], ...found[0]];
  }

  Future<List<SubtitleTitle>> _search(String type, String query) async {
    final q = Uri.encodeComponent(query.trim());
    final json = await _get('$_catalog/$type/top/search=$q.json');
    return [
      for (final m in (json['metas'] as List? ?? const []))
        if (_imdbId(m as Map<String, dynamic>) case final id?)
          SubtitleTitle(
            imdbId: id,
            name: m['name'].toString(),
            isSeries: type == 'series',
            year: m['releaseInfo']?.toString(),
          ),
    ];
  }

  String? _imdbId(Map<String, dynamic> meta) {
    final id = (meta['imdb_id'] ?? meta['id'])?.toString();
    return id != null && id.startsWith('tt') ? id : null;
  }

  Future<List<SubtitleInfo>> subtitles(
    SubtitleTitle title, {
    int season = 1,
    int episode = 1,
  }) async {
    final path = title.isSeries
        ? 'series/${title.imdbId}:$season:$episode'
        : 'movie/${title.imdbId}';
    final json = await _get('$_subtitles/$path.json');
    return [
      for (final s in (json['subtitles'] as List? ?? const []))
        SubtitleInfo.fromJson(addonName, s as Map<String, dynamic>),
    ];
  }

  Future<Map<String, dynamic>> _get(String url) async {
    final res = await _client.get(Uri.parse(url)).timeout(_timeout);
    if (res.statusCode != 200) throw 'HTTP ${res.statusCode}';
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }
}
