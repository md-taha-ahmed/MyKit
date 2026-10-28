import '../entities/stremio_entities.dart';
import '../entities/torrent_stream_status.dart';

class MoviesException implements Exception {
  const MoviesException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class MoviesRepository {
  // Add-ons
  List<String> getAddonUrls();
  Future<void> saveAddonUrls(List<String> manifestUrls);
  Future<AddonManifest> fetchManifest(String manifestUrl);

  // Content (each call goes to the add-ons that support it)
  Future<List<MetaPreview>> catalog(CatalogDef catalog, {int skip = 0});
  Future<List<MetaPreview>> search(
    List<AddonManifest> addons,
    MediaType type,
    String query,
  );
  Future<MetaDetail> meta(List<AddonManifest> addons, String type, String id);

  /// Streams from every stream add-on, emitted as each one answers.
  Stream<List<StreamSource>> streams(
    List<AddonManifest> addons,
    String type,
    String videoId,
  );
  Future<List<SubtitleInfo>> subtitles(
    List<AddonManifest> addons,
    String type,
    String videoId,
  );

  // Torrent streaming
  Future<TorrentStreamStatus> startTorrent(StreamSource source);
  Future<TorrentStreamStatus?> torrentStatus(String id);
  Future<void> stopTorrent(String id);
  Future<void> warmUpTorrents();

  // Watch history & settings
  List<WatchEntry> getHistory();
  Future<void> saveHistory(List<WatchEntry> history);
  String getSubtitleLanguage();
  Future<void> saveSubtitleLanguage(String lang);
}
