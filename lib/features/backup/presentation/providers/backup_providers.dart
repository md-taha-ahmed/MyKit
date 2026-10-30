import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../../core/google/google_oauth.dart';
import '../../../../core/storage/shared_preferences_provider.dart';
import '../../data/datasources/backup_native_data_source.dart';
import '../../data/datasources/drive_backup_data_source.dart';
import '../../data/services/backup_archive.dart';
import '../../data/services/backup_scheduler.dart';
import '../../data/services/backup_service.dart';
import '../../domain/entities/drive_backup.dart';

const backupAccent = Color(0xFF4C8DF6);

// ---------------------------------------------------------------------------
// Dependencies
// ---------------------------------------------------------------------------

final backupNativeProvider = Provider<BackupNativeDataSource>(
  (ref) => BackupNativeDataSource(),
);

final driveBackupProvider = Provider<DriveBackupDataSource>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return DriveBackupDataSource(ref.watch(googleOAuthProvider), client);
});

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(
    ref.watch(sharedPreferencesProvider),
    BackupArchive(
      ref.watch(sharedPreferencesProvider),
      ref.watch(backupNativeProvider),
    ),
    ref.watch(driveBackupProvider),
  ),
);

/// Backups in Drive, newest first (empty until signed in).
final driveBackupsProvider = FutureProvider.autoDispose<List<DriveBackup>>((
  ref,
) {
  final drive = ref.watch(driveBackupProvider);
  return drive.isSignedIn ? drive.list() : Future.value(const []);
});

// ---------------------------------------------------------------------------
// Backup state
// ---------------------------------------------------------------------------

enum BackupActivity { idle, backingUp, restoring }

class BackupStatus {
  const BackupStatus({
    required this.auto,
    this.activity = BackupActivity.idle,
    this.lastBackupAt,
    this.error,
  });

  /// Back up automatically after leaving the app.
  final bool auto;
  final BackupActivity activity;
  final DateTime? lastBackupAt;

  /// Why the last automatic backup failed, if it did.
  final String? error;

  bool get busy => activity != BackupActivity.idle;
}

final backupProvider = NotifierProvider<BackupNotifier, BackupStatus>(
  BackupNotifier.new,
);

class BackupNotifier extends Notifier<BackupStatus> {
  BackupService get _service => ref.read(backupServiceProvider);
  BackupActivity _activity = BackupActivity.idle;

  @override
  BackupStatus build() => _read();

  BackupStatus _read() {
    final service = ref.read(backupServiceProvider);
    return BackupStatus(
      auto: service.auto,
      activity: _activity,
      lastBackupAt: service.lastBackupAt,
      error: service.lastError,
    );
  }

  void _set(BackupActivity activity) {
    _activity = activity;
    state = _read();
  }

  Future<void> setAuto(bool on) async {
    await _service.setAuto(on);
    if (!on) await BackupScheduler.cancel();
    state = _read();
  }

  /// Leaving the app: schedule a backup a little later (WorkManager).
  Future<void> onLeave() async {
    if (_service.auto && _service.drive.isSignedIn && !state.busy) {
      await BackupScheduler.schedule();
    }
  }

  /// Back in the app: cancel the pending backup and pick up what a
  /// background run recorded.
  Future<void> onReturn() async {
    await BackupScheduler.cancel();
    await ref.read(sharedPreferencesProvider).reload();
    state = _read();
    ref.invalidate(driveBackupsProvider);
  }

  /// Signs in to Google Drive (browser), then backs up straight away.
  Future<void> signIn() async {
    await _service.drive.signIn();
    ref.invalidate(driveBackupsProvider);
    await backUpNow();
  }

  /// Uploads a backup even if nothing changed. Throws [BackupException].
  Future<void> backUpNow() async {
    if (state.busy) return;
    _set(BackupActivity.backingUp);
    try {
      await _service.backUp(interactive: true, onlyIfChanged: false);
    } finally {
      _set(BackupActivity.idle);
      ref.invalidate(driveBackupsProvider);
    }
  }

  /// Replaces all data with [backup] and restarts the app. Throws
  /// [BackupException].
  Future<void> restore(DriveBackup backup) async {
    if (state.busy) return;
    _set(BackupActivity.restoring);
    try {
      await BackupScheduler.cancel();
      await _service.restore(backup);
      await ref.read(backupNativeProvider).restart();
    } finally {
      _set(BackupActivity.idle);
    }
  }
}
