import '../../../../core/i18n/i18n.dart';

/// An audio file on the device.
class Track {
  const Track({
    required this.id,
    required this.uri,
    required this.title,
    required this.fileName,
    required this.folderPath,
    required this.duration,
    required this.dateAdded,
    this.artist,
    this.album,
  });

  final String id;

  /// `content://` URI used for playback and artwork.
  final String uri;

  /// Title from the file's tags (falls back to the file name).
  final String title;
  final String fileName;

  /// Absolute folder path, e.g. `/storage/emulated/0/Music/Chill`.
  final String folderPath;
  final Duration duration;
  final DateTime dateAdded;
  final String? artist;
  final String? album;

  /// File name without extension.
  String get baseName {
    final dot = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(0, dot) : fileName;
  }

  String displayName(TrackNameSource source) =>
      source == TrackNameSource.fileName ? baseName : title;
}

/// What a track is called (and sorted by) in lists.
enum TrackNameSource {
  title('Song title'),
  fileName('File name');

  const TrackNameSource(this._label);
  final String _label;
  String get label => tr(_label);
}

enum TrackSort {
  nameAsc('Name (A–Z)'),
  nameDesc('Name (Z–A)'),
  recentlyAdded('Recently added');

  const TrackSort(this._label);
  final String _label;
  String get label => tr(_label);
}

/// A folder that directly contains audio files.
class MusicFolder {
  const MusicFolder({
    required this.path,
    required this.name,
    required this.tracks,
  });

  final String path;
  final String name;
  final List<Track> tracks;

  Duration get totalDuration =>
      tracks.fold(Duration.zero, (sum, t) => sum + t.duration);
}
