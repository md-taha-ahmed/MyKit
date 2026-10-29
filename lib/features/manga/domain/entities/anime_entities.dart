/// Models for Aniyomi anime sources (the anime half of the Manga tool).
library;

/// How a title lists its content (Aniyomi `FetchType`).
enum AnimeFetchType { episodes, seasons }

class Anime {
  const Anime({
    required this.sourceId,
    required this.url,
    required this.title,
    this.artist,
    this.author,
    this.description,
    this.genre,
    this.status = 0,
    this.thumbnailUrl,
    this.backgroundUrl,
    this.fetchType = AnimeFetchType.episodes,
    this.seasonNumber = -1,
    this.initialized = false,
    this.memo = '',
  });

  final String sourceId;
  final String url;
  final String title;
  final String? artist;
  final String? author;
  final String? description;
  final String? genre;
  final int status;
  final String? thumbnailUrl;
  final String? backgroundUrl;
  final AnimeFetchType fetchType;
  final double seasonNumber;
  final bool initialized;

  /// Per-entry state from the source (JSON), passed back unchanged.
  final String memo;

  String get key => 'anime|$sourceId|$url';

  List<String> get genres => (genre ?? '')
      .split(',')
      .map((g) => g.trim())
      .where((g) => g.isNotEmpty)
      .toList();

  /// Details fill in what the listing didn't have.
  Anime merge(Anime details) => Anime(
    sourceId: sourceId,
    url: url,
    title: details.title.isNotEmpty ? details.title : title,
    artist: details.artist ?? artist,
    author: details.author ?? author,
    description: details.description ?? description,
    genre: details.genre ?? genre,
    status: details.status != 0 ? details.status : status,
    thumbnailUrl: (details.thumbnailUrl?.isNotEmpty ?? false)
        ? details.thumbnailUrl
        : thumbnailUrl,
    backgroundUrl: details.backgroundUrl ?? backgroundUrl,
    fetchType: details.fetchType,
    seasonNumber: details.seasonNumber,
    initialized: true,
    memo: details.memo.isNotEmpty ? details.memo : memo,
  );

  Map<String, Object?> toMap() => {
    'url': url,
    'title': title,
    'artist': artist,
    'author': author,
    'description': description,
    'genre': genre,
    'status': status,
    'thumbnailUrl': thumbnailUrl,
    'backgroundUrl': backgroundUrl,
    'fetchType': fetchType == AnimeFetchType.seasons ? 'Seasons' : 'Episodes',
    'seasonNumber': seasonNumber,
    'initialized': initialized,
    'memo': memo,
  };

  factory Anime.fromMap(String sourceId, Map<Object?, Object?> m) => Anime(
    sourceId: sourceId,
    url: m['url'] as String,
    title: m['title'] as String? ?? '',
    artist: m['artist'] as String?,
    author: m['author'] as String?,
    description: m['description'] as String?,
    genre: m['genre'] as String?,
    status: (m['status'] as num?)?.toInt() ?? 0,
    thumbnailUrl: m['thumbnailUrl'] as String?,
    backgroundUrl: m['backgroundUrl'] as String?,
    fetchType: m['fetchType'] == 'Seasons'
        ? AnimeFetchType.seasons
        : AnimeFetchType.episodes,
    seasonNumber: (m['seasonNumber'] as num?)?.toDouble() ?? -1,
    initialized: m['initialized'] as bool? ?? false,
    memo: m['memo'] as String? ?? '',
  );

  Map<String, Object?> toJson() => {'sourceId': sourceId, ...toMap()};

  factory Anime.fromJson(Map<String, dynamic> j) =>
      Anime.fromMap(j['sourceId'] as String, j);
}

class AnimesPage {
  const AnimesPage(this.animes, this.hasNextPage);

  final List<Anime> animes;
  final bool hasNextPage;
}

class AnimeEpisode {
  const AnimeEpisode({
    required this.url,
    required this.name,
    this.dateUpload = 0,
    this.episodeNumber = -1,
    this.scanlator,
    this.summary,
    this.previewUrl,
    this.filler = false,
    this.memo = '',
  });

  final String url;
  final String name;

  /// Milliseconds since epoch, 0 if unknown.
  final int dateUpload;
  final double episodeNumber;
  final String? scanlator;
  final String? summary;
  final String? previewUrl;
  final bool filler;
  final String memo;

  Map<String, Object?> toMap() => {
    'url': url,
    'name': name,
    'dateUpload': dateUpload,
    'episodeNumber': episodeNumber,
    'scanlator': scanlator,
    'summary': summary,
    'previewUrl': previewUrl,
    'filler': filler,
    'memo': memo,
  };

  factory AnimeEpisode.fromMap(Map<Object?, Object?> m) => AnimeEpisode(
    url: m['url'] as String,
    name: m['name'] as String? ?? '',
    dateUpload: (m['dateUpload'] as num?)?.toInt() ?? 0,
    episodeNumber: (m['episodeNumber'] as num?)?.toDouble() ?? -1,
    scanlator: m['scanlator'] as String?,
    summary: m['summary'] as String?,
    previewUrl: m['previewUrl'] as String?,
    filler: m['filler'] as bool? ?? false,
    memo: m['memo'] as String? ?? '',
  );
}

/// A video as listed by a source; [token] refers to it on the native side.
class AnimeVideo {
  const AnimeVideo({
    required this.token,
    required this.title,
    this.resolution,
    this.preferred = false,
  });

  final String token;
  final String title;
  final int? resolution;
  final bool preferred;

  factory AnimeVideo.fromMap(Map<Object?, Object?> m) => AnimeVideo(
    token: m['token'] as String,
    title: m['title'] as String? ?? '',
    resolution: (m['resolution'] as num?)?.toInt(),
    preferred: m['preferred'] as bool? ?? false,
  );
}

/// A hosting site (lib 16); old sources give one unnamed hoster.
class AnimeHoster {
  const AnimeHoster({
    required this.token,
    this.name,
    this.lazy = false,
    this.videos,
  });

  final String token;
  final String? name;
  final bool lazy;

  /// Null until loaded (lazy hosters, or loading failed).
  final List<AnimeVideo>? videos;

  factory AnimeHoster.fromMap(Map<Object?, Object?> m) => AnimeHoster(
    token: m['token'] as String,
    name: m['name'] as String?,
    lazy: m['lazy'] as bool? ?? false,
    videos: (m['videos'] as List?)
        ?.cast<Map<Object?, Object?>>()
        .map(AnimeVideo.fromMap)
        .toList(),
  );
}

typedef MediaTrack = ({String url, String lang});

/// What the player needs: final URL, request headers and extra tracks.
class ResolvedVideo {
  const ResolvedVideo({
    required this.url,
    required this.title,
    this.headers = const {},
    this.subtitles = const [],
    this.audios = const [],
  });

  final String url;
  final String title;
  final Map<String, String> headers;
  final List<MediaTrack> subtitles;
  final List<MediaTrack> audios;

  factory ResolvedVideo.fromMap(Map<Object?, Object?> m) {
    List<MediaTrack> tracks(Object? raw) => [
      for (final t in (raw as List? ?? const []).cast<Map<Object?, Object?>>())
        (url: t['url'] as String, lang: t['lang'] as String? ?? ''),
    ];
    return ResolvedVideo(
      url: m['url'] as String,
      title: m['title'] as String? ?? '',
      headers: {
        for (final e in ((m['headers'] as Map?) ?? const {}).entries)
          e.key as String: e.value as String,
      },
      subtitles: tracks(m['subtitles']),
      audios: tracks(m['audios']),
    );
  }
}

class AnimeLibraryEntry {
  const AnimeLibraryEntry({
    required this.anime,
    required this.addedAt,
    this.watchedEpisodes = const {},
    this.lastEpisodeUrl,
    this.lastWatchedAt,
  });

  final Anime anime;
  final DateTime addedAt;
  final Set<String> watchedEpisodes;
  final String? lastEpisodeUrl;
  final DateTime? lastWatchedAt;

  AnimeLibraryEntry copyWith({
    Anime? anime,
    Set<String>? watchedEpisodes,
    String? lastEpisodeUrl,
    DateTime? lastWatchedAt,
  }) => AnimeLibraryEntry(
    anime: anime ?? this.anime,
    addedAt: addedAt,
    watchedEpisodes: watchedEpisodes ?? this.watchedEpisodes,
    lastEpisodeUrl: lastEpisodeUrl ?? this.lastEpisodeUrl,
    lastWatchedAt: lastWatchedAt ?? this.lastWatchedAt,
  );

  Map<String, Object?> toJson() => {
    'anime': anime.toJson(),
    'addedAt': addedAt.toIso8601String(),
    'watched': watchedEpisodes.toList(),
    'lastEpisodeUrl': lastEpisodeUrl,
    'lastWatchedAt': lastWatchedAt?.toIso8601String(),
  };

  factory AnimeLibraryEntry.fromJson(Map<String, dynamic> j) =>
      AnimeLibraryEntry(
        anime: Anime.fromJson(j['anime'] as Map<String, dynamic>),
        addedAt: DateTime.parse(j['addedAt'] as String),
        watchedEpisodes: {...(j['watched'] as List? ?? const []).cast()},
        lastEpisodeUrl: j['lastEpisodeUrl'] as String?,
        lastWatchedAt: DateTime.tryParse(j['lastWatchedAt'] as String? ?? ''),
      );
}
