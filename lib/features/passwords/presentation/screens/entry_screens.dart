import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/widgets/dialogs.dart';
import '../../domain/entities/vault_entry.dart';
import '../../passwords_routes.dart';
import '../providers/vault_providers.dart';
import '../widgets/vault_widgets.dart';
import 'passwords_home_screen.dart';

/// Leaves for the lock screen as soon as the vault locks.
class VaultGuard extends ConsumerWidget {
  const VaultGuard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unlocked = ref.watch(
      vaultProvider.select((s) => s.status == VaultStatus.unlocked),
    );
    if (!unlocked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(PasswordsRoutes.home);
      });
      return const Scaffold();
    }
    return SecureScope(child: child);
  }
}

// ---------------------------------------------------------------------------
// Details
// ---------------------------------------------------------------------------

class EntryScreen extends ConsumerStatefulWidget {
  const EntryScreen({super.key, required this.entryId});

  final String entryId;

  @override
  ConsumerState<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends ConsumerState<EntryScreen> {
  bool _reveal = false;

  @override
  Widget build(BuildContext context) {
    final vault = ref.watch(vaultProvider);
    final e = vault.byId(widget.entryId);
    return VaultGuard(
      child: e == null
          ? Scaffold(
              appBar: AppBar(),
              body: Center(child: Text(tr('Not found.'))),
            )
          : _details(context, e, vault.reusedPasswords.contains(e.password)),
    );
  }

  Widget _details(BuildContext context, VaultEntry e, bool reused) {
    final notifier = ref.read(vaultProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: e.favorite
                ? tr('Remove from favourites')
                : tr('Favourite'),
            icon: Icon(
              e.favorite ? Icons.star : Icons.star_border,
              color: e.favorite ? const Color(0xFFF5C518) : null,
            ),
            onPressed: () => notifier.toggleFavorite(e.id),
          ),
          IconButton(
            tooltip: tr('Edit'),
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.push(PasswordsRoutes.edit(e.id)),
          ),
          PopupMenuButton<String>(
            onSelected: (_) async {
              final ok = await showConfirmDialog(
                context,
                title: tr('Delete "{title}"?', {'title': e.title}),
                message: tr('This password will be removed from the vault.'),
              );
              if (ok) {
                await notifier.delete(e.id);
                if (context.mounted) context.pop();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'delete', child: Text(tr('Delete'))),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Row(
            children: [
              EntryAvatar(label: e.host.isNotEmpty ? e.host : e.title),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  e.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (e.username.isNotEmpty)
            _Field(
              label: tr('Username'),
              value: e.username,
              onCopy: () =>
                  copySecret(context, ref, e.username, tr('Username')),
            ),
          _Field(
            label: tr('Password'),
            value: _reveal ? e.password : '•' * e.password.length.clamp(8, 16),
            monospace: _reveal,
            extra: IconButton(
              tooltip: _reveal ? tr('Hide') : tr('Show'),
              icon: Icon(_reveal ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _reveal = !_reveal),
            ),
            onCopy: () => copySecret(context, ref, e.password, tr('Password')),
            footer: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StrengthMeter(e.password),
                if (reused)
                  Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      tr(
                        'Also used for another login. A unique password per site is safer.',
                      ),
                      style: TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 13,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (e.url.isNotEmpty)
            _Field(
              label: tr('Website'),
              value: e.url,
              extra: IconButton(
                tooltip: tr('Open'),
                icon: const Icon(Icons.open_in_new),
                onPressed: () => launchUrl(
                  Uri.parse(e.url.contains('://') ? e.url : 'https://${e.url}'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              onCopy: () => copySecret(context, ref, e.url, tr('Website')),
            ),
          if (e.notes.isNotEmpty)
            _Field(label: tr('Notes'), value: e.notes, multiline: true),
          const SizedBox(height: 12),
          Text(
            [
              tr('Updated {date}', {
                'date': DateFormat('d MMM y').format(e.updatedAt),
              }),
              if (e.passwordChangedAt != null)
                tr('password set {date}', {
                  'date': DateFormat('d MMM y').format(e.passwordChangedAt!),
                }),
            ].join(' · '),
            style: const TextStyle(color: Colors.white38, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.value,
    this.onCopy,
    this.extra,
    this.footer,
    this.monospace = false,
    this.multiline = false,
  });

  final String label;
  final String value;
  final VoidCallback? onCopy;
  final Widget? extra;
  final Widget? footer;
  final bool monospace;
  final bool multiline;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 12.5),
          ),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  value,
                  maxLines: multiline ? null : 1,
                  style: TextStyle(
                    fontSize: 16,
                    fontFamily: monospace ? 'monospace' : null,
                  ),
                ),
              ),
              ?extra,
              if (onCopy != null)
                IconButton(
                  tooltip: tr('Copy'),
                  icon: const Icon(Icons.copy, size: 20),
                  onPressed: onCopy,
                ),
            ],
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.only(right: 10, bottom: 4),
              child: footer,
            ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Add / edit
// ---------------------------------------------------------------------------

class EntryEditScreen extends ConsumerStatefulWidget {
  const EntryEditScreen({super.key, this.entryId});

  /// Null to add a new entry.
  final String? entryId;

  @override
  ConsumerState<EntryEditScreen> createState() => _EntryEditScreenState();
}

class _EntryEditScreenState extends ConsumerState<EntryEditScreen> {
  late final VaultEntry? _original = widget.entryId == null
      ? null
      : ref.read(vaultProvider).byId(widget.entryId!);
  late final _title = TextEditingController(text: _original?.title);
  late final _username = TextEditingController(text: _original?.username);
  late final _password = TextEditingController(text: _original?.password);
  late final _url = TextEditingController(text: _original?.url);
  late final _notes = TextEditingController(text: _original?.notes);
  bool _show = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_title, _username, _password, _url, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    var title = _title.text.trim();
    if (title.isEmpty) {
      final url = _url.text.trim();
      title = url.isEmpty
          ? ''
          : (Uri.tryParse(url.contains('://') ? url : 'https://$url')?.host ??
                    url)
                .replaceFirst('www.', '');
    }
    if (title.isEmpty || _password.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Add a name (or website) and a password.'))),
      );
      return;
    }
    setState(() => _saving = true);
    final notifier = ref.read(vaultProvider.notifier);
    final original = _original;
    if (original == null) {
      await notifier.add(
        title: title,
        username: _username.text,
        password: _password.text,
        url: _url.text,
        notes: _notes.text,
      );
    } else {
      await notifier.update(
        original.copyWith(
          title: title,
          username: _username.text.trim(),
          password: _password.text,
          url: _url.text.trim(),
          notes: _notes.text.trim(),
        ),
      );
    }
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return VaultGuard(
      child: Scaffold(
        appBar: AppBar(
          title: Text(_original == null ? tr('New password') : tr('Edit')),
          actions: [
            TextButton(
              onPressed: _saving ? null : _save,
              child: Text(tr('Save')),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: tr('Name'),
                hintText: tr('e.g. Gmail, Bank, Netflix'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: tr('Website (optional)'),
                hintText: 'example.com',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _username,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: tr('Username or email')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: !_show,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) => setState(() {}),
              style: TextStyle(fontFamily: _show ? 'monospace' : null),
              decoration: InputDecoration(
                labelText: tr('Password'),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: _show ? tr('Hide') : tr('Show'),
                      icon: Icon(
                        _show ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setState(() => _show = !_show),
                    ),
                    IconButton(
                      tooltip: tr('Generate'),
                      icon: const Icon(Icons.casino_outlined),
                      onPressed: () async {
                        final p = await showPasswordGenerator(context);
                        if (p != null) {
                          setState(() {
                            _password.text = p;
                            _show = true;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            StrengthMeter(_password.text),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: tr('Notes (optional)'),
                hintText: tr('Security questions, recovery codes…'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
