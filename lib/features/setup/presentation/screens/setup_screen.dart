import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/ai/gemini_key_screen.dart';
import '../../../../core/i18n/i18n.dart';
import '../../../backup/backup_routes.dart';
import '../../../limiter/presentation/providers/limiter_providers.dart';
import '../../../passwords/passwords_routes.dart';
import '../providers/setup_providers.dart';
import 'settings_screen.dart';

/// First-run checklist (also under Settings): each item says what it's for,
/// whether it's done, and fixes it with one tap.
class SetupScreen extends ConsumerWidget {
  const SetupScreen({super.key, this.firstRun = false});

  /// Opened automatically on a fresh install: shows the welcome and the
  /// language choice, and "Start using MyKit" at the end.
  final bool firstRun;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = ref.watch(setupStatusProvider).value ?? const SetupStatus();
    final refresh = ref.read(setupStatusProvider.notifier).refresh;
    final native = ref.read(setupNativeProvider);

    Future<void> finish() async {
      await ref.read(setupDoneProvider.notifier).markDone();
      if (!context.mounted) return;
      context.canPop() ? context.pop() : context.go('/');
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(firstRun ? tr('Welcome to MyKit') : tr('Setup')),
        automaticallyImplyLeading: !firstRun,
        actions: [
          if (firstRun) TextButton(onPressed: finish, child: Text(tr('Skip'))),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            if (firstRun) ...[
              Text(
                tr(
                  'A few one-time steps make everything work. Each one takes a minute, and you can do them later from Settings.',
                ),
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
              ),
              const SizedBox(height: 16),
              Text(tr('Language'), style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              const LanguagePicker(),
              const SizedBox(height: 20),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    tr('Recommended'),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text(
                  tr('{done} of {total} done', {
                    'done': status.essentialsDone,
                    'total': SetupStatus.essentials,
                  }),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _Item(
              icon: Icons.notifications_outlined,
              title: tr('Notifications'),
              why: tr(
                'Reminders, the daily lesson, screen-time warnings and new articles.',
              ),
              done: status.notifications,
              action: tr('Allow'),
              onTap: () async {
                final android = FlutterLocalNotificationsPlugin()
                    .resolvePlatformSpecificImplementation<
                      AndroidFlutterLocalNotificationsPlugin
                    >();
                final ok = await android?.requestNotificationsPermission();
                // Refused before: Android won't ask again, so open settings.
                if (ok != true) await native.openAppSettings();
                await refresh();
              },
            ),
            _Item(
              icon: Icons.battery_charging_full_outlined,
              title: tr('Run in the background'),
              why: tr(
                'Lets backups, site checks and music keep working when MyKit is closed. Some phones (OnePlus, Xiaomi, Samsung) stop apps otherwise.',
              ),
              done: status.battery,
              action: tr('Allow'),
              onTap: () async {
                await native.requestBattery();
                await refresh();
              },
            ),
            _Item(
              icon: Icons.auto_awesome_outlined,
              title: tr('AI features (Gemini)'),
              why: tr(
                'Article summaries and chat, and lesson explanations. Needs a free key from Google (2 minutes).',
              ),
              done: status.ai,
              action: tr('Set up'),
              onTap: () async {
                await openGeminiKeySetup(context);
                await refresh();
              },
            ),
            _Item(
              icon: Icons.cloud_outlined,
              title: tr('Backup to Google Drive'),
              why: tr(
                'Keeps your settings, libraries, progress and passwords (encrypted) safe if you change or reset your phone.',
              ),
              done: status.backup,
              action: tr('Sign in'),
              onTap: () async {
                await context.push(BackupRoutes.home);
                await refresh();
              },
            ),
            const SizedBox(height: 20),
            Text(
              tr('For specific tools (optional)'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _Item(
              icon: Icons.lock_outline,
              title: tr('Passwords'),
              why: tr(
                'Create a master password to keep your logins in an encrypted vault.',
              ),
              done: status.passwords,
              action: tr('Create'),
              onTap: () async {
                await context.push(PasswordsRoutes.home);
                await refresh();
              },
            ),
            _Item(
              icon: Icons.password,
              title: tr('Fill passwords in apps'),
              why: tr(
                'Choose MyKit as the autofill service so your saved logins appear in apps and browsers.',
              ),
              done: status.autofill,
              action: tr('Choose'),
              onTap: () async {
                await native.requestAutofill();
                await refresh();
              },
            ),
            _Item(
              icon: Icons.hourglass_bottom,
              title: tr('Screen time'),
              why: tr(
                'Turn on "MyKit Screen time" in Accessibility so daily limits can count and block apps and sites.',
              ),
              done: status.screenTime,
              action: tr('Turn on'),
              onTap: () async {
                await ref.read(limiterNativeProvider).openSettings();
                await refresh();
              },
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: finish,
              child: Text(firstRun ? tr('Start using MyKit') : tr('Done')),
            ),
          ],
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.icon,
    required this.title,
    required this.why,
    required this.done,
    required this.action,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String why;
  final bool done;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: done ? Colors.green : theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 3),
                  Text(
                    why,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            done
                ? IconButton(
                    tooltip: tr('Open'),
                    onPressed: onTap,
                    icon: const Icon(Icons.check_circle, color: Colors.green),
                  )
                : FilledButton.tonal(onPressed: onTap, child: Text(action)),
          ],
        ),
      ),
    );
  }
}
