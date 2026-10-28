import 'dart:typed_data';

import '../entities/track.dart';

class MusicPermissionDenied implements Exception {
  const MusicPermissionDenied();
}

abstract interface class MusicLibraryRepository {
  /// Asks for audio access if needed. Returns whether it's granted.
  Future<bool> requestPermission();

  /// Opens system settings so the user can grant a denied permission.
  Future<void> openAppSettings();

  /// All audio files on the device (system sounds excluded).
  Future<List<Track>> scanTracks();

  /// Embedded cover art, or null.
  Future<Uint8List?> artwork(String trackUri, {int size});
}
