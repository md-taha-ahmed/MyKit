import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/drive_backup.dart';
import '../providers/backup_providers.dart';

class BackupScreen extends ConsumerWidget {
  const BackupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drive = ref.watch(driveBackupProvider);
    final status = ref.watch(backupProvider);
    final notifier = ref.read(backupProvider.notifier);

    Future<void> run(Future<void> Function() action, String done) async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await action();
        messenger.showSnackBar(SnackBar(content: Text(done)));
      } on Exception catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('$e')));
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Backup')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          if (!drive.isConfigured)
            const _Note(
              icon: Icons.key_off_outlined,
              text:
                  'Google sign-in isn\'t set up in this build. Add the OAuth '
                  'client (RSS Feeds → Import YouTube subscriptions) or build '
                  'with config/google_oauth.local.json.',
            )
          else if (!drive.isSignedIn) ...[
            const _Note(
              icon: Icons.cloud_outlined,
              text:
                  'Back up your settings, extensions, libraries and progress '
                  'to a private MyKit folder in your Google Drive. If the app '
                  'is ever deleted, sign in here again and restore.',
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: status.busy
                  ? null
                  : () => run(notifier.signIn, 'Backed up to Google Drive'),
              icon: status.busy ? const _Spinner() : const Icon(Icons.login),
              label: const Text('Sign in with Google'),
            ),
          ] else ...[
            _LastBackupCard(status: status),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: status.busy
                  ? null
                  : () => run(notifier.backUpNow, 'Backed up'),
              icon: status.activity == BackupActivity.backingUp
                  ? const _Spinner()
                  : const Icon(Icons.cloud_upload_outlined),
              label: const Text('Back up now'),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: const Text('Back up automatically'),
              subtitle: const Text(
                'When you leave MyKit and something has changed',
              ),
              value: status.auto,
              onChanged: notifier.setAuto,
            ),
            const SizedBox(height: 12),
            Text(
              'Backups in Google Drive',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            ref
                .watch(driveBackupsProvider)
                .when(
                  data: (backups) => backups.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            'No backups yet.',
                            style: TextStyle(color: Colors.white60),
                          ),
                        )
                      : Column(
                          children: [
                            for (final b in backups)
                              _BackupTile(
                                backup: b,
                                enabled: !status.busy,
                                onRestore: () async {
                                  if (await _confirmRestore(context, b)) {
                                    await run(
                                      () => notifier.restore(b),
                                      'Restored. Restarting…',
                                    );
                                  }
                                },
                              ),
                          ],
                        ),
                  loading: () => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      '$e',
                      style: const TextStyle(color: Colors.white60),
                    ),
                  ),
                ),
            const SizedBox(height: 20),
            Text(
              'Included: all settings, extensions and their settings, '
              'libraries, watch/reading progress, feeds, countdowns and '
              'workouts. Not included: imported book PDFs and downloaded '
              'or cached files. The last ${BackupNotifier.keep} backups are '
              'kept.',
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Colors.white54,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Future<bool> _confirmRestore(
    BuildContext context,
    DriveBackup b,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Restore this backup?'),
          content: Text(
            'Everything in MyKit on this phone is replaced with the backup '
            'from ${DateFormat('d MMM y, HH:mm').format(b.createdAt)}. '
            'MyKit restarts afterwards.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restore'),
            ),
          ],
        ),
      ) ??
      false;
}

class _LastBackupCard extends StatelessWidget {
  const _LastBackupCard({required this.status});

  final BackupStatus status;

  @override
  Widget build(BuildContext context) {
    final last = status.lastBackupAt;
    final failed = status.error;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              failed != null ? Icons.cloud_off_outlined : Icons.cloud_done,
              color: failed != null
                  ? Colors.orangeAccent
                  : Theme.of(context).colorScheme.primary,
              size: 32,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    last == null
                        ? 'No backup yet'
                        : 'Last backup ${_ago(last)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (failed != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Automatic backup failed: $failed',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    if (d.inDays == 1) return 'yesterday';
    if (d.inDays < 7) return '${d.inDays} days ago';
    return 'on ${DateFormat('d MMM y').format(t)}';
  }
}

class _BackupTile extends StatelessWidget {
  const _BackupTile({
    required this.backup,
    required this.enabled,
    required this.onRestore,
  });

  final DriveBackup backup;
  final bool enabled;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final kb = backup.sizeBytes / 1024;
    final size = kb < 1024
        ? '${kb.toStringAsFixed(0)} KB'
        : '${(kb / 1024).toStringAsFixed(1)} MB';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: const Icon(Icons.history),
      title: Text(DateFormat('EEE d MMM y, HH:mm').format(backup.createdAt)),
      subtitle: Text(size),
      trailing: TextButton(
        onPressed: enabled ? onRestore : null,
        child: const Text('Restore'),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
        ],
      ),
    ),
  );
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 18,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}
