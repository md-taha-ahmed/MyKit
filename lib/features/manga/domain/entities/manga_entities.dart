import '../../../../core/i18n/i18n.dart';

/// A Mihon-compatible extension repository the user added.
class ExtensionRepo {
  const ExtensionRepo({
    required this.url,
    required this.name,
    required this.signingKey,
    this.website,
  });

  /// URL as entered (e.g. `.../index.min.json`); re-resolved on refresh.
  final String url;
  final String name;

  /// SHA-256 of the certificate every extension from this repo must be signed with.
  final String signingKey;
  final String? website;
}

enum ContentWarning { unspecified, safe, mixed, nsfw }

class AvailableSource {
  const AvailableSource({
    required this.id,
    required this.name,
    required this.lang,
    this.homeUrl = '',
  });

  final String id;
  final String name;
  final String lang;
  final String homeUrl;
}

/// An extension listed in a repository (not necessarily installed).
class AvailableExtension {
  const AvailableExtension({
    required this.name,
    required this.pkgName,
    required this.apkUrl,
    required this.iconUrl,
    required this.libVersion,
    required this.versionCode,
    required this.versionName,
    required this.contentWarning,
    required this.sources,
    required this.repo,
    this.isTorrent = false,
  });

  final String name;
  final String pkgName;
  final String apkUrl;
  final String iconUrl;
  final String libVersion;
  final int versionCode;
  final String versionName;
  final ContentWarning contentWarning;
  final List<AvailableSource> sources;
  final ExtensionRepo repo;

  /// Anime extension whose videos are torrents (needs Aniyomi's torrent server).
  final bool isTorrent;

  /// Aniyomi anime extension (vs a Mihon manga extension).
  bool get isAnime => pkgName.contains('.animeextension.');

  /// Aniyomi counts "mixed" content as NSFW too.
  bool get isNsfw => isAnime
      ? contentWarning.index >= ContentWarning.mixed.index
      : contentWarning == ContentWarning.nsfw;

  /// "en", "all", … like Mihon.
  String get lang {
    final langs = sources.map((s) => s.lang).toSet();
    return langs.length == 1 ? langs.first : 'all';
  }

  static const supportedLibs = {'1.4', '1.6'};
  static const supportedAnimeLibs = {'14', '16', '17'};

  bool get isSupported => isAnime
      ? supportedAnimeLibs.contains(libVersion) && !isTorrent
      : supportedLibs.contains(libVersion);
}

/// A source exposed by an installed extension.
class MangaSource {
  const MangaSource({
    required this.id,
    required this.name,
    required this.lang,
    required this.supportsLatest,
    this.baseUrl,
    required this.extensionName,
    required this.pkgName,
    required this.nsfw,
  });

  final String id;
  final String name;
  final String lang;
  final bool supportsLatest;
  final String? baseUrl;
  final String extensionName;
  final String pkgName;
  final bool nsfw;
}

class InstalledExtension {
  const InstalledExtension({
    required this.pkgName,
    required this.name,
    required this.versionName,
    required this.versionCode,
    required this.libVersion,
    required this.nsfw,
    required this.sources,
  });

  final String pkgName;
  final String name;
  final String versionName;
  final int versionCode;
  final double libVersion;
  final bool nsfw;
  final List<MangaSource> sources;
}

enum MangaStatus {
  unknown('Unknown'),
  ongoing('Ongoing'),
  completed('Completed'),
  licensed('Licensed'),
  publishingFinished('Publishing finished'),
  cancelled('Cancelled'),
  onHiatus('On hiatus');

  const MangaStatus(this._label);
  final String _label;
  String get label => tr(_label);

  static MangaStatus of(int? code) =>
      code != null && code >= 0 && code < values.length
      ? values[code]
      : MangaStatus.unknown;
}

class Manga {
  const Manga({
    required this.sourceId,
    required this.url,
    required this.title,
    this.artist,
    this.author,
    this.description,
    this.genre,
    this.status = 0,
    this.thumbnailUrl,
    this.initialized = false,
    this.memo = '{}',
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
  final bool initialized;

  /// Extension-private state (lib 1.6), passed back unchanged.
  final String memo;

  /// Unique across sources.
  String get key => '$sourceId|$url';

  List<String> get genres => (genre ?? '')
      .split(',')
      .map((g) => g.trim())
      .where((g) => g.isNotEmpty)
      .toList();

  /// Merges fresh details, keeping known values the source didn't return.
  Manga merge(Manga d) => Manga(
    sourceId: sourceId,
    url: url,
    title: d.title.isEmpty ? title : d.title,
    artist: d.artist ?? artist,
    author: d.author ?? author,
    description: d.description ?? description,
    genre: d.genre ?? genre,
    status: d.status,
    thumbnailUrl: d.thumbnailUrl ?? thumbnailUrl,
    initialized: true,
    memo: d.memo,
  );

  Map<String, Object?> toMap() => {
    'sourceId': sourceId,
    'url': url,
    'title': title,
    'artist': artist,
    'author': author,
    'description': description,
    'genre': genre,
    'status': status,
    'thumbnailUrl': thumbnailUrl,
    'initialized': initialized,
    'memo': memo,
  };

  factory Manga.fromMap(String sourceId, Map<Object?, Object?> m) => Manga(
    sourceId: sourceId,
    url: m['url'] as String,
    title: m['title'] as String? ?? '',
    artist: m['artist'] as String?,
    author: m['author'] as String?,
    description: m['description'] as String?,
    genre: m['genre'] as String?,
    status: (m['status'] as num?)?.toInt() ?? 0,
    thumbnailUrl: m['thumbnailUrl'] as String?,
    initialized: m['initialized'] as bool? ?? false,
    memo: m['memo'] as String? ?? '{}',
  );
}

class MangasPage {
  const MangasPage(this.mangas, this.hasNextPage);

  final List<Manga> mangas;
  final bool hasNextPage;
}

class Chapter {
  const Chapter({
    required this.url,
    required this.name,
    this.dateUpload = 0,
    this.chapterNumber = -1,
    this.scanlator,
    this.memo = '{}',
  });

  final String url;
  final String name;

  /// Epoch millis (0 = unknown).
  final int dateUpload;
  final double chapterNumber;
  final String? scanlator;
  final String memo;

  Map<String, Object?> toMap() => {
    'url': url,
    'name': name,
    'dateUpload': dateUpload,
    'chapterNumber': chapterNumber,
    'scanlator': scanlator,
    'memo': memo,
  };

  factory Chapter.fromMap(Map<Object?, Object?> m) => Chapter(
    url: m['url'] as String,
    name: m['name'] as String? ?? '',
    dateUpload: (m['dateUpload'] as num?)?.toInt() ?? 0,
    chapterNumber: (m['chapterNumber'] as num?)?.toDouble() ?? -1,
    scanlator: m['scanlator'] as String?,
    memo: m['memo'] as String? ?? '{}',
  );
}

class ReaderPage {
  const ReaderPage({required this.index, required this.url, this.imageUrl});

  final int index;
  final String url;
  final String? imageUrl;

  Map<String, Object?> toMap() => {
    'index': index,
    'url': url,
    'imageUrl': imageUrl,
  };
}

/// A manga saved to the library, with reading progress.
class LibraryEntry {
  const LibraryEntry({
    required this.manga,
    required this.addedAt,
    this.lastChapterUrl,
    this.lastPage = 0,
    this.lastReadAt,
    this.readChapters = const {},
  });

  final Manga manga;
  final DateTime addedAt;
  final String? lastChapterUrl;

  /// 0-based page within [lastChapterUrl].
  final int lastPage;
  final DateTime? lastReadAt;
  final Set<String> readChapters;

  LibraryEntry copyWith({
    Manga? manga,
    String? lastChapterUrl,
    int? lastPage,
    DateTime? lastReadAt,
    Set<String>? readChapters,
  }) => LibraryEntry(
    manga: manga ?? this.manga,
    addedAt: addedAt,
    lastChapterUrl: lastChapterUrl ?? this.lastChapterUrl,
    lastPage: lastPage ?? this.lastPage,
    lastReadAt: lastReadAt ?? this.lastReadAt,
    readChapters: readChapters ?? this.readChapters,
  );
}

enum MangaReadingMode {
  rightToLeft('Right to left', 'Manga'),
  leftToRight('Left to right', 'Comics'),
  vertical('Vertical', 'Webtoon / long strip');

  const MangaReadingMode(this._label, this._hint);
  final String _label;
  String get label => tr(_label);
  final String _hint;
  String get hint => tr(_hint);
}
