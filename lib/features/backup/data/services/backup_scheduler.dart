import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../domain/entities/drive_backup.dart';
import 'backup_service.dart';

/// Automatic backups through Android's WorkManager.
///
/// Leaving the app schedules one backup [delay] later; coming back cancels
/// it, so opening and closing the app often still uploads once, after you've
/// really put it down. WorkManager runs it even if Android has killed MyKit
/// by then, waits for a network connection and retries failures with backoff.
abstract final class BackupScheduler {
  static const delay = Duration(minutes: 2);
  static const _uniqueName = 'mykit.backup.auto';
  static const task = 'backup';

  static Future<void> schedule() => Workmanager().registerOneOffTask(
    _uniqueName,
    task,
    initialDelay: delay,
    existingWorkPolicy: ExistingWorkPolicy.replace,
    constraints: Constraints(networkType: NetworkType.connected),
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(minutes: 5),
  );

  static Future<void> cancel() => Workmanager().cancelByUniqueName(_uniqueName);
}

/// The automatic backup, run by WorkManager (see `app/background_tasks.dart`).
/// True when done, false to retry later.
Future<bool> runBackupTask() async {
  final prefs = await SharedPreferences.getInstance();
  // The app may have changed things since this isolate's cache was filled.
  await prefs.reload();
  final client = http.Client();
  final service = BackupService.create(prefs, client);
  try {
    if (!service.auto || !service.drive.isSignedIn) return true;
    await service.backUp(interactive: false, onlyIfChanged: true);
    return true;
  } on SocketException {
    return false; // offline after all: retry later
  } on http.ClientException {
    return false;
  } on BackupException catch (e) {
    // Signed out, Drive full, API off…: retrying won't help; show it.
    await service.setLastError(e.message);
    return true;
  } catch (e) {
    await service.setLastError('$e');
    return false;
  } finally {
    client.close();
  }
}
