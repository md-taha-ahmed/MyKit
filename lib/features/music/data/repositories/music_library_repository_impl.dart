import 'dart:typed_data';

import '../../domain/entities/track.dart';
import '../../domain/repositories/music_library_repository.dart';
import '../datasources/media_store_data_source.dart';

class MusicLibraryRepositoryImpl implements MusicLibraryRepository {
  MusicLibraryRepositoryImpl(this._mediaStore);

  final MediaStoreDataSource _mediaStore;

  @override
  Future<bool> requestPermission() => _mediaStore.requestPermission();

  @override
  Future<void> openAppSettings() => _mediaStore.openAppSettings();

  @override
  Future<List<Track>> scanTracks() async {
    if (!await requestPermission()) throw const MusicPermissionDenied();
    return _mediaStore.getTracks();
  }

  @override
  Future<Uint8List?> artwork(String trackUri, {int size = 256}) =>
      _mediaStore.getArtwork(trackUri, size);
}
