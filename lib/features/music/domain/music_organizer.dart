import '../../../core/utils/natural_sort.dart';
import 'entities/track.dart';

/// Pure grouping/sorting of the music library.
abstract final class MusicOrganizer {
  /// Groups [tracks] by folder. Folders are always A–Z by name; tracks
  /// inside follow [sort].
  static List<MusicFolder> folders(
    List<Track> tracks, {
    required TrackSort sort,
    required TrackNameSource nameSource,
  }) {
    final byPath = <String, List<Track>>{};
    for (final t in tracks) {
      (byPath[t.folderPath] ??= []).add(t);
    }

    final folders =
        [
          for (final e in byPath.entries)
            MusicFolder(
              path: e.key,
              name: folderName(e.key),
              tracks: sortTracks(e.value, sort: sort, nameSource: nameSource),
            ),
        ]..sort((a, b) {
          final c = naturalCompare(a.name, b.name);
          return c != 0 ? c : naturalCompare(a.path, b.path);
        });
    return folders;
  }

  static List<Track> sortTracks(
    List<Track> tracks, {
    required TrackSort sort,
    required TrackNameSource nameSource,
  }) {
    int byName(Track a, Track b) =>
        naturalCompare(a.displayName(nameSource), b.displayName(nameSource));

    final sorted = [...tracks];
    switch (sort) {
      case TrackSort.nameAsc:
        sorted.sort(byName);
      case TrackSort.nameDesc:
        sorted.sort((a, b) => byName(b, a));
      case TrackSort.recentlyAdded:
        sorted.sort((a, b) {
          final c = b.dateAdded.compareTo(a.dateAdded);
          return c != 0 ? c : byName(a, b);
        });
    }
    return sorted;
  }

  static String folderName(String path) {
    final trimmed = path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    final slash = trimmed.lastIndexOf('/');
    final name = slash >= 0 ? trimmed.substring(slash + 1) : trimmed;
    return name.isEmpty ? 'Internal storage' : name;
  }

  /// Path shown under a folder name, without the storage root.
  static String friendlyPath(String path) => path
      .replaceFirst(RegExp(r'^/storage/emulated/\d+/?'), '')
      .replaceFirst(RegExp(r'^/sdcard/?'), '');
}
