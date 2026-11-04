import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/i18n/i18n.dart';
import '../../data/services/vault_crypto.dart';
import '../providers/vault_providers.dart';
import '../widgets/vault_widgets.dart';
import 'entry_screens.dart';

class VaultSettingsScreen extends ConsumerWidget {
  const VaultSettingsScreen({super.key});

  static const _autoLockChoices = [
    (Duration(seconds: 30), '30 seconds'),
    (Duration(minutes: 1), '1 minute'),
    (Duration(minutes: 5), '5 minutes'),
    (Duration(minutes: 15), '15 minutes'),
  ];

  void _snack(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(vaultProvider.notifier);
    final files = await notifier.withoutAutoLock(
      () => FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
      ),
    );
    final path = files.firstOrNull?.path;
    if (path == null) return;
    try {
      final csv = utf8.decode(
        await File(path).readAsBytes(),
        allowMalformed: true,
      );
      final (added, skipped) = await notifier.importCsv(csv);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle_outline, size: 36),
          title: Text(
            added == 1
                ? tr('Imported 1 password')
                : tr('Imported {n} passwords', {'n': added}),
          ),
          content: Text(
            [
              if (skipped > 0)
                tr('{n} were already in the vault.', {'n': skipped}),
              tr(
                'The CSV file is not encrypted: delete it from your phone (and from Downloads / Drive) now that it\'s imported.',
              ),
            ].join('\n\n'),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } on FormatException catch (e) {
      if (context.mounted) _snack(context, e.message);
    } catch (e) {
      if (context.mounted) {
        _snack(context, tr('Could not import: {e}', {'e': e}));
      }
    } finally {
      // The picker's cached copy holds every password in plain text.
      await FilePicker.clearTemporaryFiles();
    }
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber, size: 36, color: Colors.orange),
        title: Text(tr('Export unencrypted?')),
        content: Text(
          tr(
            'The CSV file will contain all your passwords in plain text. Anyone or any app that can read the file can read them. Use it only to move to another password manager, then delete it.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Export')),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final notifier = ref.read(vaultProvider.notifier);
    final saved = await notifier.withoutAutoLock(
      () => FilePicker.saveFile(
        fileName:
            'mykit-passwords-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.csv',
        bytes: utf8.encode(notifier.exportCsv()),
        mimeType: 'text/csv',
      ),
    );
    if (saved != null && context.mounted) {
      _snack(
        context,
        tr('Exported. Delete the file when you\'re done with it.'),
      );
    }
  }

  Future<void> _changeMaster(BuildContext context, WidgetRef ref) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => const _ChangeMasterDialog(),
    );
    if (changed == true && context.mounted) {
      _snack(context, tr('Master password changed.'));
    }
  }

  Future<void> _deleteVault(BuildContext context, WidgetRef ref) async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => _PasswordPrompt(
        title: tr('Delete the vault?'),
        message: tr(
          'Every saved password is erased from this phone. Your Drive backups keep their copies until they are replaced. Enter your master password to confirm.',
        ),
        action: tr('Delete everything'),
      ),
    );
    if (password == null) return;
    try {
      await ref.read(vaultProvider.notifier).deleteVault(password);
    } on VaultException catch (e) {
      if (context.mounted) _snack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vault = ref.watch(vaultProvider);
    final notifier = ref.read(vaultProvider.notifier);
    return VaultGuard(
      child: Scaffold(
        appBar: AppBar(title: Text(tr('Password settings'))),
        body: ListView(
          children: [
            _Header(tr('Unlocking')),
            SwitchListTile(
              secondary: const Icon(Icons.fingerprint),
              title: Text(tr('Unlock with fingerprint')),
              subtitle: Text(
                vault.biometricAvailable
                    ? tr(
                        'If your fingerprints change, or on a new phone, you\'ll need the master password.',
                      )
                    : tr('No fingerprint is set up on this phone.'),
              ),
              value: vault.biometricEnabled,
              onChanged: !vault.biometricAvailable
                  ? null
                  : (on) async {
                      if (!on) return notifier.disableBiometric();
                      final message = await notifier.enableBiometric();
                      if (message != null && context.mounted) {
                        _snack(context, message);
                      }
                    },
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text(tr('Lock after leaving MyKit for')),
              trailing: DropdownButton<Duration>(
                value: vault.autoLock,
                underline: const SizedBox.shrink(),
                items: [
                  for (final (d, label) in _autoLockChoices)
                    DropdownMenuItem(value: d, child: Text(tr(label))),
                ],
                onChanged: (d) => d == null ? null : notifier.setAutoLock(d),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.password),
              title: Text(tr('Change master password')),
              onTap: () => _changeMaster(context, ref),
            ),
            _Header(tr('Autofill')),
            const _AutofillTile(),
            ListTile(
              leading: const Icon(Icons.link_off),
              title: Text(tr('Forget app links')),
              subtitle: Text(
                tr('Logins picked for apps are suggested there next time'),
              ),
              onTap: () async {
                await ref.read(vaultNativeProvider).clearAutofillLinks();
                if (context.mounted) {
                  _snack(context, tr('App links forgotten.'));
                }
              },
            ),
            _Header(tr('Import & export')),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: Text(tr('Import from CSV')),
              subtitle: Text(
                tr(
                  'From Chrome / Google Password Manager, Bitwarden, Firefox, KeePass…',
                ),
              ),
              onTap: () => _import(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: Text(tr('Export to CSV')),
              subtitle: Text(tr('Unencrypted; for moving elsewhere')),
              onTap: () => _export(context, ref),
            ),
            _Header(tr('Backup')),
            ListTile(
              leading: Icon(Icons.cloud_done_outlined),
              title: Text(tr('Included in your Google Drive backup')),
              subtitle: Text(
                tr(
                  'Only in encrypted form. Restoring on a new phone needs your master password.',
                ),
              ),
            ),
            const Divider(height: 24),
            ListTile(
              leading: const Icon(
                Icons.delete_forever_outlined,
                color: Colors.redAccent,
              ),
              title: Text(
                tr('Delete vault'),
                style: TextStyle(color: Colors.redAccent),
              ),
              onTap: () => _deleteVault(context, ref),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        letterSpacing: 1,
        color: passwordsAccent,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// Asks for the master password; returns it, or null if cancelled.
class _PasswordPrompt extends StatefulWidget {
  const _PasswordPrompt({
    required this.title,
    required this.message,
    required this.action,
  });

  final String title;
  final String message;
  final String action;

  @override
  State<_PasswordPrompt> createState() => _PasswordPromptState();
}

class _PasswordPromptState extends State<_PasswordPrompt> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.message),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(labelText: tr('Master password')),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(tr('Cancel')),
      ),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
        onPressed: () => Navigator.pop(context, _controller.text),
        child: Text(widget.action),
      ),
    ],
  );
}

class _ChangeMasterDialog extends ConsumerStatefulWidget {
  const _ChangeMasterDialog();

  @override
  ConsumerState<_ChangeMasterDialog> createState() =>
      _ChangeMasterDialogState();
}

class _ChangeMasterDialogState extends ConsumerState<_ChangeMasterDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_next.text.length < 8) {
      setState(() => _error = tr('Use at least 8 characters.'));
      return;
    }
    if (_next.text != _confirm.text) {
      setState(() => _error = tr('The new passwords don\'t match.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(vaultProvider.notifier)
          .changeMasterPassword(_current.text, _next.text);
      if (mounted) Navigator.pop(context, true);
    } on VaultException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message == tr('Wrong master password.')
              ? tr('The current password is wrong.')
              : e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(tr('Change master password')),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _current,
            obscureText: true,
            decoration: InputDecoration(labelText: tr('Current password')),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _next,
            obscureText: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: tr('New password')),
          ),
          StrengthMeter(_next.text),
          const SizedBox(height: 10),
          TextField(
            controller: _confirm,
            obscureText: true,
            decoration: InputDecoration(labelText: tr('New password again')),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.orangeAccent),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: Text(tr('Cancel')),
      ),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: _busy
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(tr('Change')),
      ),
    ],
  );
}

/// Autofill on/off status; re-checked when coming back from Settings.
class _AutofillTile extends ConsumerStatefulWidget {
  const _AutofillTile();

  @override
  ConsumerState<_AutofillTile> createState() => _AutofillTileState();
}

class _AutofillTileState extends ConsumerState<_AutofillTile> {
  bool? _enabled;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _check);
    _check();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final on = await ref.read(vaultNativeProvider).autofillEnabled();
    if (mounted) setState(() => _enabled = on);
  }

  @override
  Widget build(BuildContext context) {
    final vault = ref.watch(vaultProvider);
    final on = _enabled ?? false;
    return Column(
      children: [
        ListTile(
          leading: Icon(
            on ? Icons.check_circle : Icons.password,
            color: on ? const Color(0xFF34C759) : null,
          ),
          title: Text(
            on ? tr('Autofill is on') : tr('Fill passwords in apps & Chrome'),
          ),
          subtitle: Text(
            !vault.biometricEnabled
                ? tr(
                    'Turn on fingerprint unlock first: autofill opens the vault with your fingerprint.',
                  )
                : on
                ? tr('Tap a login field, then "Unlock MyKit to fill".')
                : tr('Choose MyKit as your phone\'s autofill service.'),
          ),
          trailing: on
              ? TextButton(
                  onPressed: () =>
                      ref.read(vaultNativeProvider).openAutofillSettings(),
                  child: Text(tr('Change')),
                )
              : FilledButton(
                  onPressed: () async {
                    final opened = await ref
                        .read(vaultNativeProvider)
                        .openAutofillSettings();
                    if (!opened && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            tr(
                              'Open Settings → Passwords & accounts → Autofill service, and pick MyKit.',
                            ),
                          ),
                        ),
                      );
                    }
                  },
                  child: Text(tr('Turn on')),
                ),
        ),
        if (on)
          ListTile(
            leading: Icon(Icons.public),
            title: Text(tr('Chrome')),
            subtitle: Text(
              tr(
                'In Chrome: Settings → Autofill services → "Autofill using another service", then restart Chrome.',
              ),
            ),
          ),
      ],
    );
  }
}
