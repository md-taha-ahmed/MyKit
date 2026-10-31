import 'package:workmanager/workmanager.dart';

import '../features/backup/data/services/backup_scheduler.dart';
import '../features/knowledge/data/source_check_task.dart';

/// Once, in `main()`. Android allows one WorkManager entry point per app, so
/// every feature's background job goes through [backgroundTaskDispatcher].
Future<void> initBackgroundTasks() =>
    Workmanager().initialize(backgroundTaskDispatcher);

/// WorkManager's entry point (its own engine, or the app's when it's alive).
@pragma('vm:entry-point')
void backgroundTaskDispatcher() {
  Workmanager().executeTask(
    (task, input) => switch (task) {
      BackupScheduler.task => runBackupTask(),
      SourceCheckScheduler.task => runSourceCheck(),
      _ => Future.value(true),
    },
  );
}
