import 'package:flutter/services.dart';

import '../../domain/entities/drive_backup.dart';

/// Android-side state Flutter can't read itself — extension APKs, their trust
/// keys and per-source settings (`android/.../backup/BackupChannel.kt`).
class BackupNativeDataSource {
  static const _channel = MethodChannel('com.mdtaha.mykit/backup');

  /// `{prefs: {file: {key: [tag, value]}}, files: {path: bytes}}`.
  Future<Map<String, Object?>> export() async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>('export');
      return _plain(raw ?? const {}) as Map<String, Object?>;
    } on PlatformException catch (e) {
      throw BackupException(e.message ?? 'Could not read app data.');
    }
  }

  Future<void> import(Map<String, Object?> data) async {
    try {
      await _channel.invokeMethod<void>('import', data);
    } on PlatformException catch (e) {
      throw BackupException(e.message ?? 'Could not write app data.');
    }
  }

  /// Relaunches MyKit in a fresh process.
  Future<void> restart() => _channel.invokeMethod<void>('restart');

  /// Channel maps arrive as `Map<Object?, Object?>`; make them JSON-shaped
  /// (file contents stay bytes).
  static Object? _plain(Object? v) => switch (v) {
    Uint8List() => v,
    Map() => {for (final e in v.entries) '${e.key}': _plain(e.value)},
    List() => [for (final x in v) _plain(x)],
    _ => v,
  };
}
