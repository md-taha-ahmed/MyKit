import 'package:flutter_test/flutter_test.dart';
import 'package:mykit/core/utils/natural_sort.dart';
import 'package:mykit/features/music/domain/entities/track.dart';
import 'package:mykit/features/music/domain/music_organizer.dart';

Track _t(String folder, String file, {String? title, int added = 0}) => Track(
  id: '$folder/$file',
  uri: 'content://media/$file',
  title: title ?? file.split('.').first,
  fileName: file,
  folderPath: folder,
  duration: const Duration(minutes: 3),
  dateAdded: DateTime.fromMillisecondsSinceEpoch(added),
);

void main() {
  test('natural sort orders numbers by value, ignoring case', () {
    final names = ['Track 10', 'track 2', 'Track 1', 'Alpha', 'beta'];
    names.sort(naturalCompare);
    expect(names, ['Alpha', 'beta', 'Track 1', 'track 2', 'Track 10']);
  });

  test('groups by folder, folders A–Z, tracks by chosen sort', () {
    final tracks = [
      _t('/storage/emulated/0/Music/Workout', '10 Run.mp3', added: 3),
      _t('/storage/emulated/0/Music/Chill', 'b.mp3', added: 1),
      _t('/storage/emulated/0/Music/Workout', '2 Warmup.mp3', added: 5),
      _t('/storage/emulated/0/Music/Chill', 'a.mp3', added: 2),
    ];

    final asc = MusicOrganizer.folders(
      tracks,
      sort: TrackSort.nameAsc,
      nameSource: TrackNameSource.fileName,
    );
    expect(asc.map((f) => f.name), ['Chill', 'Workout']);
    expect(asc[1].tracks.map((t) => t.baseName), ['2 Warmup', '10 Run']);

    final recent = MusicOrganizer.folders(
      tracks,
      sort: TrackSort.recentlyAdded,
      nameSource: TrackNameSource.fileName,
    );
    expect(recent[0].tracks.map((t) => t.baseName), ['a', 'b']);
    expect(recent[1].tracks.map((t) => t.baseName), ['2 Warmup', '10 Run']);
  });

  test('title vs file name', () {
    final t = _t('/x', 'track01.mp3', title: 'Sunrise');
    expect(t.displayName(TrackNameSource.title), 'Sunrise');
    expect(t.displayName(TrackNameSource.fileName), 'track01');
  });

  test('friendly paths', () {
    expect(
      MusicOrganizer.friendlyPath('/storage/emulated/0/Music/Chill'),
      'Music/Chill',
    );
    expect(
      MusicOrganizer.folderName('/storage/emulated/0/Download'),
      'Download',
    );
  });
}
