/// Models of the Stremio add-on protocol
/// (https://github.com/Stremio/stremio-addon-sdk/tree/master/docs/api).
library;

import '../../../../core/i18n/i18n.dart';

/// `movie` / `series` (Stremio's content types).
enum MediaType {
  movie('movie', 'Movies'),
  series('series', 'Series');

  const MediaType(this.id, this._label);

  final String id;
  final String _label;
  String get label => tr(_label);

  static MediaType? fromId(String? id) =>
      values.where((t) => t.id == id).firstOrNull;
}

/// One catalog an add-on offers (e.g. Cinemeta's "Popular" movies).
class CatalogDef {
  const CatalogDef({
    required this.addonUrl,
    required this.type,
    required this.id,
    required this.name,
    required this.extraSupported,
    required this.extraRequired,
  });

  final String addonUrl;
  final String type;
  final String id;
  final String name;
  final Set<String> extraSupported;
  final Set<String> extraRequired;

  bool get searchable => extraSupported.contains('search');

  @override
  bool operator ==(Object other) =>
      other is CatalogDef &&
      other.addonUrl == addonUrl &&
      other.type == type &&
      other.id == id;

  @override
  int get hashCode => Object.hash(addonUrl, type, id);

  /// Shown on the home page (needs no extra arguments).
  bool get browsable => extraRequired.isEmpty;
}

/// A resource (`catalog`, `meta`, `stream`, `subtitles`) and what it covers.
class AddonResource {
  const AddonResource(this.name, this.types, this.idPrefixes);

  final String name;
  final Set<String>? types;
  final Set<String>? idPrefixes;
}

/// An installed add-on, from its `manifest.json`.
class AddonManifest {
  const AddonManifest({
    required this.transportUrl,
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.logo,
    required this.types,
    required this.idPrefixes,
    required this.resources,
    required this.catalogs,
    required this.configurable,
  });

  /// Base URL (the manifest URL without `/manifest.json`).
  final String transportUrl;
  final String id;
  final String name;
  final String version;
  final String description;
  final String? logo;
  final Set<String> types;
  final Set<String>? idPrefixes;
  final List<AddonResource> resources;
  final List<CatalogDef> catalogs;
  final bool configurable;

  String get manifestUrl => '$transportUrl/manifest.json';

  /// Whether this add-on serves [resource] for this [type] / [id].
  bool supports(String resource, String type, String id) {
    for (final r in resources) {
      if (r.name != resource) continue;
      final types = r.types ?? this.types;
      final prefixes = r.idPrefixes ?? idPrefixes;
      if (!types.contains(type)) continue;
      if (prefixes != null &&
          prefixes.isNotEmpty &&
          !prefixes.any(id.startsWith)) {
        continue;
      }
      return true;
    }
    return false;
  }

  factory AddonManifest.fromJson(String transportUrl, Map<String, dynamic> j) {
    Set<String>? strings(Object? v) =>
        v is List ? v.map((e) => e.toString()).toSet() : null;

    final types = strings(j['types']) ?? <String>{};
    final resources = <AddonResource>[
      for (final r in (j['resources'] as List? ?? const []))
        if (r is String)
          AddonResource(r, null, null)
        else if (r is Map)
          AddonResource(
            r['name'].toString(),
            strings(r['types']),
            strings(r['idPrefixes']),
          ),
    ];
    final catalogs = <CatalogDef>[
      for (final c in (j['catalogs'] as List? ?? const []).whereType<Map>())
        CatalogDef(
          addonUrl: transportUrl,
          type: c['type'].toString(),
          id: c['id'].toString(),
          name: (c['name'] ?? c['id']).toString(),
          extraSupported: {
            ...?strings(c['extraSupported']),
            for (final e in (c['extra'] as List? ?? const []).whereType<Map>())
              e['name'].toString(),
          },
          extraRequired: {
            ...?strings(c['extraRequired']),
            for (final e in (c['extra'] as List? ?? const []).whereType<Map>())
              if (e['isRequired'] == true) e['name'].toString(),
          },
        ),
    ];
    final hints = j['behaviorHints'];
    return AddonManifest(
      transportUrl: transportUrl,
      id: j['id'].toString(),
      name: (j['name'] ?? j['id']).toString(),
      version: (j['version'] ?? '').toString(),
      description: (j['description'] ?? '').toString(),
      logo: j['logo'] as String?,
      types: types,
      idPrefixes: strings(j['idPrefixes']),
      resources: resources,
      catalogs: catalogs,
      configurable: hints is Map && hints['configurable'] == true,
    );
  }
}

/// A title in a catalog or search result.
class MetaPreview {
  const MetaPreview({
    required this.id,
    required this.type,
    required this.name,
    this.poster,
    this.background,
    this.releaseInfo,
    this.imdbRating,
  });

  final String id;
  final String type;
  final String name;
  final String? poster;
  final String? background;
  final String? releaseInfo;
  final String? imdbRating;

  factory MetaPreview.fromJson(Map<String, dynamic> j) => MetaPreview(
    id: j['id'].toString(),
    type: j['type'].toString(),
    name: (j['name'] ?? '').toString(),
    poster: j['poster'] as String?,
    background: j['background'] as String?,
    releaseInfo: j['releaseInfo']?.toString(),
    imdbRating: j['imdbRating']?.toString(),
  );
}

/// An episode of a series (Stremio "video").
class Episode {
  const Episode({
    required this.id,
    required this.season,
    required this.number,
    required this.title,
    this.overview,
    this.thumbnail,
    this.released,
  });

  /// Stream id, e.g. `tt0903747:1:2`.
  final String id;
  final int season;
  final int number;
  final String title;
  final String? overview;
  final String? thumbnail;
  final DateTime? released;

  String get code =>
      'S${season.toString().padLeft(2, '0')}E${number.toString().padLeft(2, '0')}';

  bool get isUpcoming => released != null && released!.isAfter(DateTime.now());

  factory Episode.fromJson(Map<String, dynamic> j) => Episode(
    id: j['id'].toString(),
    season: (j['season'] as num?)?.toInt() ?? 0,
    number: ((j['episode'] ?? j['number']) as num?)?.toInt() ?? 0,
    title: (j['name'] ?? j['title'] ?? '').toString(),
    overview: (j['overview'] ?? j['description'])?.toString(),
    thumbnail: j['thumbnail'] as String?,
    released: DateTime.tryParse((j['released'] ?? '').toString()),
  );
}

/// Full details of a title.
class MetaDetail {
  const MetaDetail({
    required this.preview,
    this.description,
    this.logo,
    this.runtime,
    this.genres = const [],
    this.cast = const [],
    this.director = const [],
    this.episodes = const [],
  });

  final MetaPreview preview;
  final String? description;
  final String? logo;
  final String? runtime;
  final List<String> genres;
  final List<String> cast;
  final List<String> director;
  final List<Episode> episodes;

  String get id => preview.id;
  String get type => preview.type;
  String get name => preview.name;

  /// Seasons in order, specials (season 0) last.
  List<int> get seasons {
    final s = episodes.map((e) => e.season).toSet().toList()..sort();
    if (s.remove(0)) s.add(0);
    return s;
  }

  factory MetaDetail.fromJson(Map<String, dynamic> j) {
    List<String> strings(Object? v) =>
        v is List ? v.map((e) => e.toString()).toList() : const [];
    final episodes =
        [
          for (final v in (j['videos'] as List? ?? const []).whereType<Map>())
            Episode.fromJson(v.cast<String, dynamic>()),
        ]..sort(
          (a, b) => (
            _seasonOrder(a),
            a.number,
          ).compareTo((_seasonOrder(b), b.number)),
        );
    return MetaDetail(
      preview: MetaPreview.fromJson(j),
      description: j['description']?.toString(),
      logo: j['logo'] as String?,
      runtime: j['runtime']?.toString(),
      genres: strings(j['genres'] ?? j['genre']),
      cast: strings(j['cast']),
      director: strings(j['director']),
      episodes: episodes,
    );
  }
}

/// Specials (season 0) sort after the regular seasons.
int _seasonOrder(Episode e) => e.season == 0 ? 1 << 30 : e.season;

extension on (int, int) {
  int compareTo((int, int) other) {
    final c = $1.compareTo(other.$1);
    return c != 0 ? c : $2.compareTo(other.$2);
  }
}

/// A playable source returned by a stream add-on (e.g. Torrentio).
class StreamSource {
  const StreamSource({
    required this.addonName,
    required this.name,
    required this.title,
    this.url,
    this.infoHash,
    this.fileIdx,
    this.sources = const [],
    this.filename,
    this.externalUrl,
  });

  final String addonName;
  final String name;
  final String title;

  /// Direct HTTP link (e.g. Torrentio configured with a debrid service).
  final String? url;
  final String? infoHash;
  final int? fileIdx;

  /// `tracker:<url>` / `dht:<hash>` peer sources.
  final List<String> sources;
  final String? filename;
  final String? externalUrl;

  bool get isTorrent => infoHash != null;
  bool get isPlayable => url != null || infoHash != null;

  List<String> get trackers => [
    for (final s in sources)
      if (s.startsWith('tracker:')) s.substring('tracker:'.length),
  ];

  /// First line of [name] after the add-on name, e.g. "4k HDR" / "1080p".
  String get quality {
    final lines = name.split('\n').map((l) => l.trim()).toList();
    if (lines.length > 1) return lines.sublist(1).join(' ');
    return resolution == 'Other' ? '—' : resolution;
  }

  /// [title] without the trailing stats line(s).
  String get release => title
      .split('\n')
      .where((l) => !l.contains('👤') && !l.contains('💾'))
      .join('\n')
      .trim();

  int? get seeders =>
      int.tryParse(RegExp(r'👤\s*(\d+)').firstMatch(title)?.group(1) ?? '');

  String? get size =>
      RegExp(r'💾\s*([\d.,]+\s*[KMGT]?B)').firstMatch(title)?.group(1);

  String? get provider =>
      RegExp(r'⚙️\s*([^\n]+)').firstMatch(title)?.group(1)?.trim();

  /// Coarse bucket used by the quality filter.
  String get resolution {
    final q = '$name $title'.toLowerCase();
    if (q.contains('2160') || q.contains('4k')) return '4K';
    if (q.contains('1080')) return '1080p';
    if (q.contains('720')) return '720p';
    if (q.contains('480') || q.contains('sd')) return 'SD';
    return 'Other';
  }

  factory StreamSource.fromJson(String addonName, Map<String, dynamic> j) {
    final hints = j['behaviorHints'];
    return StreamSource(
      addonName: addonName,
      name: (j['name'] ?? addonName).toString(),
      title: (j['title'] ?? j['description'] ?? '').toString(),
      url: j['url'] as String?,
      infoHash: (j['infoHash'] as String?)?.toLowerCase(),
      fileIdx: (j['fileIdx'] as num?)?.toInt(),
      sources: [
        for (final s in (j['sources'] as List? ?? const [])) s.toString(),
      ],
      filename: hints is Map ? hints['filename'] as String? : null,
      externalUrl: j['externalUrl'] as String?,
    );
  }

  Map<String, Object?> toJson() => {
    'addonName': addonName,
    'name': name,
    'title': title,
    'url': url,
    'infoHash': infoHash,
    'fileIdx': fileIdx,
    'sources': sources,
    'behaviorHints': {'filename': filename},
    'externalUrl': externalUrl,
  };
}

/// A subtitle file from a subtitles add-on (e.g. OpenSubtitles v3).
class SubtitleInfo {
  const SubtitleInfo({
    required this.id,
    required this.url,
    required this.lang,
    required this.addonName,
  });

  final String id;
  final String url;

  /// ISO 639-2 code as sent by the add-on (e.g. `eng`).
  final String lang;
  final String addonName;

  /// Codes ("eng") map to names; sources that already send names keep them.
  String get languageName =>
      languageNames[lang] ?? (lang.length > 3 ? lang : lang.toUpperCase());

  factory SubtitleInfo.fromJson(String addonName, Map<String, dynamic> j) =>
      SubtitleInfo(
        id: j['id'].toString(),
        url: j['url'].toString(),
        lang: (j['lang'] ?? 'und').toString(),
        addonName: addonName,
      );
}

/// Normalises a subtitle language to a code: add-ons send codes ("eng"),
/// anime sources send names ("English", "Portuguese (Brazil)").
String languageCode(String raw) {
  if (languageNames.containsKey(raw)) return raw;
  final lower = raw.toLowerCase();
  for (final e in languageNames.entries) {
    if (lower.startsWith(e.value.toLowerCase())) return e.key;
  }
  return raw;
}

/// Names for the language codes OpenSubtitles returns most.
const languageNames = <String, String>{
  'eng': 'English',
  'ara': 'Arabic',
  'spa': 'Spanish',
  'fre': 'French',
  'fra': 'French',
  'ger': 'German',
  'deu': 'German',
  'ita': 'Italian',
  'por': 'Portuguese',
  'pob': 'Portuguese (BR)',
  'rus': 'Russian',
  'tur': 'Turkish',
  'dut': 'Dutch',
  'nld': 'Dutch',
  'pol': 'Polish',
  'swe': 'Swedish',
  'nor': 'Norwegian',
  'dan': 'Danish',
  'fin': 'Finnish',
  'gre': 'Greek',
  'ell': 'Greek',
  'heb': 'Hebrew',
  'hin': 'Hindi',
  'urd': 'Urdu',
  'ben': 'Bengali',
  'per': 'Persian',
  'fas': 'Persian',
  'ind': 'Indonesian',
  'may': 'Malay',
  'msa': 'Malay',
  'tha': 'Thai',
  'vie': 'Vietnamese',
  'chi': 'Chinese',
  'zho': 'Chinese',
  'zht': 'Chinese (Trad.)',
  'jpn': 'Japanese',
  'kor': 'Korean',
  'cze': 'Czech',
  'ces': 'Czech',
  'hun': 'Hungarian',
  'rum': 'Romanian',
  'ron': 'Romanian',
  'bul': 'Bulgarian',
  'hrv': 'Croatian',
  'scc': 'Serbian',
  'srp': 'Serbian',
  'slv': 'Slovenian',
  'ukr': 'Ukrainian',
  'est': 'Estonian',
  'lav': 'Latvian',
  'lit': 'Lithuanian',
};

/// Something partly watched, for "Continue watching" and resuming.
class WatchEntry {
  const WatchEntry({
    required this.videoId,
    required this.metaId,
    required this.type,
    required this.name,
    required this.position,
    required this.duration,
    required this.updatedAt,
    this.poster,
    this.background,
    this.episodeLabel,
  });

  /// Stream id (movie id, or `tt…:season:episode`).
  final String videoId;
  final String metaId;
  final String type;
  final String name;
  final String? poster;
  final String? background;

  /// e.g. "S01E02 · Cat's in the Bag…".
  final String? episodeLabel;
  final Duration position;
  final Duration duration;
  final DateTime updatedAt;

  double get fraction => duration.inMilliseconds <= 0
      ? 0
      : (position.inMilliseconds / duration.inMilliseconds).clamp(0, 1);

  bool get finished => fraction > 0.92;

  Map<String, Object?> toJson() => {
    'videoId': videoId,
    'metaId': metaId,
    'type': type,
    'name': name,
    'poster': poster,
    'background': background,
    'episodeLabel': episodeLabel,
    'position': position.inMilliseconds,
    'duration': duration.inMilliseconds,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory WatchEntry.fromJson(Map<String, dynamic> j) => WatchEntry(
    videoId: j['videoId'] as String,
    metaId: j['metaId'] as String,
    type: j['type'] as String,
    name: j['name'] as String,
    poster: j['poster'] as String?,
    background: j['background'] as String?,
    episodeLabel: j['episodeLabel'] as String?,
    position: Duration(milliseconds: j['position'] as int),
    duration: Duration(milliseconds: j['duration'] as int),
    updatedAt: DateTime.parse(j['updatedAt'] as String),
  );
}
