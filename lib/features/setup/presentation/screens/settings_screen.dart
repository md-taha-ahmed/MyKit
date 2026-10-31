import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/ai/gemini_client.dart';
import '../../../../core/ai/gemini_key_screen.dart';
import '../../../../core/i18n/i18n.dart';
import '../../../backup/backup_routes.dart';
import '../../setup_routes.dart';
import '../providers/setup_providers.dart';

/// App-wide settings: language, the setup checklist, AI key and backup.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = ref.watch(setupStatusProvider).value;
    final aiReady = ref.watch(geminiClientProvider).isConfigured;

    return Scaffold(
      appBar: AppBar(title: Text(tr('Settings'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Text(tr('Language'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const LanguagePicker(),
          const SizedBox(height: 24),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.checklist),
                  title: Text(tr('Setup checklist')),
                  subtitle: Text(
                    status == null
                        ? tr('Permissions and accounts MyKit needs')
                        : tr('{done} of {total} recommended steps done', {
                            'done': status.essentialsDone,
                            'total': SetupStatus.essentials,
                          }),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(SetupRoutes.setup),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: Text(tr('AI features (Gemini)')),
                  subtitle: Text(
                    aiReady
                        ? tr('Key set')
                        : tr('Not set up — tap to add a free key'),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openGeminiKeySetup(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.cloud_outlined),
                  title: Text(tr('Backup')),
                  subtitle: Text(tr('Google Drive backup and restore')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(BackupRoutes.home),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// System / English / العربية. Each option is written in its own language
/// so it can be found whatever the current one is.
class LanguagePicker extends ConsumerWidget {
  const LanguagePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(appLanguageProvider);
    return SegmentedButton<AppLanguage>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(
          value: AppLanguage.system,
          label: Text(
            I18n.isArabic
                ? AppLanguage.system.arabicLabel
                : AppLanguage.system.label,
          ),
          icon: const Icon(Icons.phone_android, size: 18),
        ),
        const ButtonSegment(value: AppLanguage.english, label: Text('English')),
        const ButtonSegment(value: AppLanguage.arabic, label: Text('العربية')),
      ],
      selected: {current},
      onSelectionChanged: (s) =>
          ref.read(appLanguageProvider.notifier).set(s.first),
    );
  }
}
