import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../../../../core/storage/shared_preferences_provider.dart';
import '../../data/datasources/media_store_data_source.dart';
import '../../data/repositories/music_library_repository_impl.dart';
import '../../data/services/music_player_service.dart';
import '../../domain/entities/track.dart';
import '../../domain/music_organizer.dart';
import '../../domain/repositories/music_library_repository.dart';

// ---------------------------------------------------------------------------
// Dependencies
// ---------------------------------------------------------------------------

final musicLibraryRepositoryProvider = Provider<MusicLibraryRepository>(
  (ref) => MusicLibraryRepositoryImpl(MediaStoreDataSource()),
);

/// The one player for the whole app (kept alive so music survives navigation).
final musicPlayerProvider = Provider<MusicPlayerService>((ref) {
  final service = MusicPlayerService();
  ref.onDispose(service.dispose);
  return service;
});

// ---------------------------------------------------------------------------
// Library
// ---------------------------------------------------------------------------

final musicLibraryProvider =
    AsyncNotifierProvider<MusicLibraryNotifier, List<Track>>(
      MusicLibraryNotifier.new,
    );

class MusicLibraryNotifier extends AsyncNotifier<List<Track>> {
  @override
  Future<List<Track>> build() =>
      ref.read(musicLibraryRepositoryProvider).scanTracks();

  Future<void> rescan() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(musicLibraryRepositoryProvider).scanTracks(),
    );
  }
}

// ---------------------------------------------------------------------------
// Sorting preferences (persisted)
// ---------------------------------------------------------------------------

typedef MusicSortSettings = ({TrackSort sort, TrackNameSource nameSource});

final musicSortProvider =
    NotifierProvider<MusicSortNotifier, MusicSortSettings>(
      MusicSortNotifier.new,
    );

class MusicSortNotifier extends Notifier<MusicSortSettings> {
  static const _sortKey = 'music.sort';
  static const _nameKey = 'music.nameSource';

  @override
  MusicSortSettings build() {
    final prefs = ref.read(sharedPreferencesProvider);
    return (
      sort:
          TrackSort.values.asNameMap()[prefs.getString(_sortKey)] ??
          TrackSort.nameAsc,
      nameSource:
          TrackNameSource.values.asNameMap()[prefs.getString(_nameKey)] ??
          TrackNameSource.title,
    );
  }

  void setSort(TrackSort sort) {
    state = (sort: sort, nameSource: state.nameSource);
    ref.read(sharedPreferencesProvider).setString(_sortKey, sort.name);
  }

  void setNameSource(TrackNameSource source) {
    state = (sort: state.sort, nameSource: source);
    ref.read(sharedPreferencesProvider).setString(_nameKey, source.name);
  }
}

// ---------------------------------------------------------------------------
// Derived views
// ---------------------------------------------------------------------------

/// Key for the virtual "All songs" folder.
const allSongsFolder = '__all__';

final musicFoldersProvider = Provider<AsyncValue<List<MusicFolder>>>((ref) {
  final settings = ref.watch(musicSortProvider);
  return ref
      .watch(musicLibraryProvider)
      .whenData(
        (tracks) => MusicOrganizer.folders(
          tracks,
          sort: settings.sort,
          nameSource: settings.nameSource,
        ),
      );
});

/// Sorted tracks of one folder ([allSongsFolder] = every track).
final folderTracksProvider = Provider.family<List<Track>, String>((ref, path) {
  final settings = ref.watch(musicSortProvider);
  final tracks = ref.watch(musicLibraryProvider).value ?? const [];
  return MusicOrganizer.sortTracks(
    path == allSongsFolder
        ? tracks
        : tracks.where((t) => t.folderPath == path).toList(),
    sort: settings.sort,
    nameSource: settings.nameSource,
  );
});

final trackArtworkProvider = FutureProvider.autoDispose
    .family<Uint8List?, String>(
      (ref, uri) => ref.read(musicLibraryRepositoryProvider).artwork(uri),
    );

// ---------------------------------------------------------------------------
// Playback state
// ---------------------------------------------------------------------------

AudioPlayer _player(Ref ref) => ref.watch(musicPlayerProvider).player;

/// Song currently loaded in the player (null when nothing is queued).
final nowPlayingProvider = StreamProvider<MediaItem?>((ref) {
  return _player(
    ref,
  ).sequenceStateStream.map((s) => s.currentSource?.tag as MediaItem?);
});

final playerStateProvider = StreamProvider<PlayerState>(
  (ref) => _player(ref).playerStateStream,
);

final playbackPositionProvider = StreamProvider<Duration>(
  (ref) => _player(ref).positionStream,
);

final playbackDurationProvider = StreamProvider<Duration?>(
  (ref) => _player(ref).durationStream,
);

final shuffleEnabledProvider = StreamProvider<bool>(
  (ref) => _player(ref).shuffleModeEnabledStream,
);

final loopModeProvider = StreamProvider<LoopMode>(
  (ref) => _player(ref).loopModeStream,
);

/// Current queue in play order.
final playQueueProvider = StreamProvider<List<MediaItem>>((ref) {
  return _player(ref).sequenceStateStream.map(
    (s) => [for (final src in s.effectiveSequence) src.tag as MediaItem],
  );
});
