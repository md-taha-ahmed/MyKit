import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'knowledge_notifications.dart';
import 'knowledge_store.dart';
import 'source_updater.dart';

/// Checks the followed sites every few hours with Android's WorkManager,
/// even when MyKit is closed, and notifies about new articles. WorkManager
/// waits for a connection and spaces the runs out to save battery.
abstract final class SourceCheckScheduler {
  static const task = 'knowledge.sources';
  static const _uniqueName = 'mykit.knowledge.sources';
  static const every = Duration(hours: 4);

  /// On when there's something to follow and alerts are wanted.
  static Future<void> sync({required bool enabled}) async {
    try {
      if (!enabled) {
        await Workmanager().cancelByUniqueName(_uniqueName);
        return;
      }
      await Workmanager().registerPeriodicTask(
        _uniqueName,
        task,
        frequency: every,
        flexInterval: const Duration(hours: 1),
        initialDelay: every,
        // Keep the running schedule; don't restart the clock on every launch.
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        constraints: Constraints(networkType: NetworkType.connected),
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(minutes: 15),
      );
    } catch (_) {
      // Tests / platforms without WorkManager.
    }
  }
}

/// The background run (its own isolate). True when done, false to retry.
Future<bool> runSourceCheck() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final store = KnowledgeStore(prefs);
  if (!store.settings.sourceAlerts || store.sources.isEmpty) return true;

  final client = http.Client();
  try {
    final update = await SourceUpdater(store, client).run();
    if (update.found.isNotEmpty) {
      final names = {for (final s in store.sources) s.id: s.name};
      final perSource = <String, int>{};
      for (final item in update.found) {
        final name = names[item.sourceId] ?? '';
        perSource[name] = (perSource[name] ?? 0) + 1;
      }
      await KnowledgeNotifications().showNewArticles(
        perSource,
        update.found.first.title,
      );
    }
    // Every site failing usually means no real connection: try again soon.
    return update.failed.length < store.sources.length;
  } on SocketException {
    return false;
  } catch (_) {
    return true;
  } finally {
    client.close();
  }
}
