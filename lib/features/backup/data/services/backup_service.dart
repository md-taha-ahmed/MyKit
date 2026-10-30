import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/google/google_oauth.dart';
import '../../domain/entities/drive_backup.dart';
import '../../domain/services/backup_retention.dart';
import '../datasources/backup_native_data_source.dart';
import '../datasources/drive_backup_data_source.dart';
import 'backup_archive.dart';

/// Backing up to and restoring from Google Drive, without Riverpod, so the
/// app and the WorkManager background task share it.
///
/// Bookkeeping lives in `backup.*` preferences, which are never part of a
/// backup (see [BackupArchive]).
class BackupService {
  BackupService(this._prefs, this.archive, this.drive);

  /// Everything wired up from [prefs] (for the background task).
  factory BackupService.create(SharedPreferences prefs, http.Client client) =>
      BackupService(
        prefs,
        BackupArchive(prefs, BackupNativeDataSource()),
        DriveBackupDataSource(GoogleOAuth(prefs, client), client),
      );

  final SharedPreferences _prefs;
  final BackupArchive archive;
  final DriveBackupDataSource drive;

  static const _autoKey = 'backup.auto';
  static const _lastAtKey = 'backup.lastAt';
  static const _lastHashKey = 'backup.lastHash';
  static const _lastErrorKey = 'backup.lastError';
  static const _namePrefix = 'mykit-backup-';

  /// Back up automatically after leaving the app (default on).
  bool get auto => _prefs.getBool(_autoKey) ?? true;
  Future<void> setAuto(bool on) => _prefs.setBool(_autoKey, on);

  DateTime? get lastBackupAt => switch (_prefs.getInt(_lastAtKey)) {
    final ms? => DateTime.fromMillisecondsSinceEpoch(ms),
    null => null,
  };

  /// Why the last automatic backup failed, until one succeeds.
  String? get lastError => _prefs.getString(_lastErrorKey);
  Future<void> setLastError(String? error) => error == null
      ? _prefs.remove(_lastErrorKey)
      : _prefs.setString(_lastErrorKey, error);

  /// Uploads a backup and thins out old ones. With [onlyIfChanged], skips the
  /// upload when nothing changed since the last backup. Returns whether it
  /// uploaded. Throws [BackupException].
  Future<bool> backUp({
    required bool interactive,
    required bool onlyIfChanged,
  }) async {
    final built = await archive.build();
    if (onlyIfChanged && built.hash == _prefs.getString(_lastHashKey)) {
      return false;
    }
    final now = DateTime.now();
    await drive.upload(
      '$_namePrefix${DateFormat('yyyyMMdd-HHmmss').format(now)}.json.gz',
      built.bytes,
      interactive: interactive,
    );
    await _prefs.setString(_lastHashKey, built.hash);
    await _prefs.setInt(_lastAtKey, now.millisecondsSinceEpoch);
    await setLastError(null);
    await _prune(now);
    return true;
  }

  /// Deletes backups the retention plan no longer needs. Best effort.
  Future<void> _prune(DateTime now) async {
    try {
      final ours = (await drive.list())
          .where((b) => b.name.startsWith(_namePrefix))
          .toList();
      final keep = backupsToKeep(ours, now);
      for (final b in ours) {
        if (!keep.contains(b.id)) await drive.delete(b.id);
      }
    } catch (_) {
      // The next backup tries again.
    }
  }

  /// Replaces all app data with [backup]. The app must restart afterwards.
  Future<void> restore(DriveBackup backup) async {
    final hash = await archive.restore(await drive.download(backup.id));
    // What's on the phone now *is* this backup: don't re-upload it.
    await _prefs.setString(_lastHashKey, hash);
  }
}
