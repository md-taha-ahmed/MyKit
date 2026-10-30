import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/google/google_oauth.dart';
import '../../../../core/storage/shared_preferences_provider.dart';
import '../../data/datasources/backup_native_data_source.dart';
import '../../data/datasources/drive_backup_data_source.dart';
import '../../data/services/backup_archive.dart';
import '../../domain/entities/drive_backup.dart';

const backupAccent = Color(0xFF4C8DF6);

// ---------------------------------------------------------------------------
// Dependencies
// ---------------------------------------------------------------------------

final backupNativeProvider = Provider<BackupNativeDataSource>(
  (ref) => BackupNativeDataSource(),
);

final backupArchiveProvider = Provider<BackupArchive>(
  (ref) => BackupArchive(
    ref.watch(sharedPreferencesProvider),
    ref.watch(backupNativeProvider),
  ),
);

final driveBackupProvider = Provider<DriveBackupDataSource>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return DriveBackupDataSource(ref.watch(googleOAuthProvider), client);
});

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

  /// Back up automatically when the app goes to the background.
  final bool auto;
  final BackupActivity activity;
  final DateTime? lastBackupAt;

  /// Why the last automatic backup failed, if it did.
  final String? error;

  bool get busy => activity != BackupActivity.idle;

  BackupStatus copyWith({
    bool? auto,
    BackupActivity? activity,
    DateTime? lastBackupAt,
    String? Function()? error,
  }) => BackupStatus(
    auto: auto ?? this.auto,
    activity: activity ?? this.activity,
    lastBackupAt: lastBackupAt ?? this.lastBackupAt,
    error: error != null ? error() : this.error,
  );
}

final backupProvider = NotifierProvider<BackupNotifier, BackupStatus>(
  BackupNotifier.new,
);

class BackupNotifier extends Notifier<BackupStatus> {
  // `backup.*` keys are never part of a backup (see BackupArchive).
  static const _autoKey = 'backup.auto';
  static const _lastAtKey = 'backup.lastAt';
  static const _lastHashKey = 'backup.lastHash';
  static const _lastCheckKey = 'backup.lastCheckAt';

  /// Backups kept in Drive; older ones are deleted.
  static const keep = 10;
  static const _checkEvery = Duration(minutes: 15);

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);
  DriveBackupDataSource get _drive => ref.read(driveBackupProvider);

  @override
  BackupStatus build() {
    final lastAt = _prefs.getInt(_lastAtKey);
    return BackupStatus(
      auto: _prefs.getBool(_autoKey) ?? true,
      lastBackupAt: lastAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastAt),
    );
  }

  Future<void> setAuto(bool on) async {
    await _prefs.setBool(_autoKey, on);
    state = state.copyWith(auto: on);
  }

  /// Signs in to Google Drive (browser), then backs up straight away.
  Future<void> signIn() async {
    await _drive.signIn();
    ref.invalidate(driveBackupsProvider);
    await backUpNow();
  }

  /// Uploads a backup even if nothing changed. Throws [BackupException].
  Future<void> backUpNow() => _backUp(interactive: true, onlyIfChanged: false);

  /// Called when the app goes to the background: backs up quietly if it's
  /// switched on, signed in and something changed. Never throws.
  Future<void> autoBackUp() async {
    if (!state.auto || state.busy || !_drive.isSignedIn) return;
    final lastCheck = _prefs.getInt(_lastCheckKey) ?? 0;
    final since = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(lastCheck),
    );
    if (since < _checkEvery) return;
    await _prefs.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);
    try {
      await _backUp(interactive: false, onlyIfChanged: true);
      if (state.error != null) state = state.copyWith(error: () => null);
    } catch (e) {
      state = state.copyWith(error: () => '$e');
    }
  }

  Future<void> _backUp({
    required bool interactive,
    required bool onlyIfChanged,
  }) async {
    if (state.busy) return;
    state = state.copyWith(activity: BackupActivity.backingUp);
    try {
      final archive = await ref.read(backupArchiveProvider).build();
      if (onlyIfChanged && archive.hash == _prefs.getString(_lastHashKey)) {
        return;
      }
      final now = DateTime.now();
      await _drive.upload(
        'mykit-backup-${DateFormat('yyyyMMdd-HHmmss').format(now)}.json.gz',
        archive.bytes,
        interactive: interactive,
      );
      await _prefs.setString(_lastHashKey, archive.hash);
      await _prefs.setInt(_lastAtKey, now.millisecondsSinceEpoch);
      state = state.copyWith(lastBackupAt: now, error: () => null);
      await _prune();
    } finally {
      state = state.copyWith(activity: BackupActivity.idle);
      ref.invalidate(driveBackupsProvider);
    }
  }

  Future<void> _prune() async {
    try {
      final old = (await _drive.list())
          .where((b) => b.name.startsWith('mykit-backup-'))
          .skip(keep);
      for (final b in old) {
        await _drive.delete(b.id);
      }
    } catch (_) {
      // Next backup tries again.
    }
  }

  /// Replaces all data with [backup] and restarts the app. Throws
  /// [BackupException].
  Future<void> restore(DriveBackup backup) async {
    if (state.busy) return;
    state = state.copyWith(activity: BackupActivity.restoring);
    try {
      final bytes = await _drive.download(backup.id);
      final hash = await ref.read(backupArchiveProvider).restore(bytes);
      // What's on the phone now *is* this backup: don't re-upload it.
      await _prefs.setString(_lastHashKey, hash);
      await ref.read(backupNativeProvider).restart();
    } finally {
      state = state.copyWith(activity: BackupActivity.idle);
    }
  }
}
