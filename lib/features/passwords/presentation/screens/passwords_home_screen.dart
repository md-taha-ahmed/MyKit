import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/services/vault_crypto.dart';
import '../../domain/entities/vault_entry.dart';
import '../../domain/services/password_tools.dart';
import '../../passwords_routes.dart';
import '../providers/vault_providers.dart';
import '../widgets/vault_widgets.dart';

/// Setup, lock screen or the list of passwords, depending on the vault.
class PasswordsHomeScreen extends ConsumerWidget {
  const PasswordsHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(vaultProvider.select((s) => s.status));
    return SecureScope(
      child: switch (status) {
        VaultStatus.noVault => const _SetupView(),
        VaultStatus.locked => const _LockView(),
        VaultStatus.unlocked => const _VaultListView(),
      },
    );
  }
}

// ---------------------------------------------------------------------------
// First run: choose a master password
// ---------------------------------------------------------------------------

class _SetupView extends ConsumerStatefulWidget {
  const _SetupView();

  @override
  ConsumerState<_SetupView> createState() => _SetupViewState();
}

class _SetupViewState extends ConsumerState<_SetupView> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _show = false;
  bool _busy = false;
  bool _understood = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final p = _password.text;
    setState(() => _error = null);
    if (p.length < 8) {
      setState(() => _error = 'Use at least 8 characters.');
      return;
    }
    if (strengthOf(p).index < PasswordStrength.fair.index) {
      setState(() => _error = 'Too easy to guess. Make it longer.');
      return;
    }
    if (p != _confirm.text) {
      setState(() => _error = 'The two passwords don\'t match.');
      return;
    }
    setState(() => _busy = true);
    final notifier = ref.read(vaultProvider.notifier);
    await notifier.create(p);
    if (!mounted) return;
    if (ref.read(vaultProvider).biometricAvailable) {
      final on = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.fingerprint, size: 36),
          title: const Text('Unlock with fingerprint?'),
          content: const Text(
            'Open your passwords with your fingerprint instead of typing '
            'the master password each time. You can change this in settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Turn on'),
            ),
          ],
        ),
      );
      if (on == true) await notifier.enableBiometric();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Passwords')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        children: [
          const Icon(Icons.lock_outline, size: 48, color: passwordsAccent),
          const SizedBox(height: 12),
          Text(
            'Create your master password',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'It encrypts every password you save here. It never leaves this '
            'phone and is never stored, so pick something long you\'ll '
            'remember, like a short sentence.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _password,
            obscureText: !_show,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Master password',
              suffixIcon: IconButton(
                icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _show = !_show),
              ),
            ),
          ),
          StrengthMeter(_password.text),
          const SizedBox(height: 12),
          TextField(
            controller: _confirm,
            obscureText: !_show,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'Type it again'),
            onSubmitted: (_) => _create(),
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _understood,
            onChanged: (v) => setState(() => _understood = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              'I understand that if I forget it, my passwords can\'t be '
              'recovered by anyone.',
              style: TextStyle(fontSize: 14),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.orangeAccent),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy || !_understood ? null : _create,
            child: _busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create vault'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Locked
// ---------------------------------------------------------------------------

class _LockView extends ConsumerStatefulWidget {
  const _LockView();

  @override
  ConsumerState<_LockView> createState() => _LockViewState();
}

class _LockViewState extends ConsumerState<_LockView> {
  final _password = TextEditingController();
  bool _show = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Offer the fingerprint straight away when it's set up.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final vault = ref.read(vaultProvider);
      if (vault.biometricEnabled) await _fingerprint();
    });
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (_password.text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(vaultProvider.notifier).unlockWithPassword(_password.text);
    } on VaultException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fingerprint() async {
    final message = await ref
        .read(vaultProvider.notifier)
        .unlockWithBiometric();
    if (message != null && mounted) setState(() => _error = message);
  }

  @override
  Widget build(BuildContext context) {
    // Fingerprint state loads asynchronously; prompt once it's known.
    ref.listen(vaultProvider.select((s) => s.biometricEnabled), (was, now) {
      if (was == false && now) _fingerprint();
    });
    final biometric = ref.watch(
      vaultProvider.select((s) => s.biometricEnabled),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Passwords')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
        children: [
          const Icon(Icons.lock, size: 56, color: passwordsAccent),
          const SizedBox(height: 16),
          Text(
            'Vault locked',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _password,
            obscureText: !_show,
            autocorrect: false,
            enableSuggestions: false,
            autofocus: !biometric,
            onSubmitted: (_) => _unlock(),
            decoration: InputDecoration(
              labelText: 'Master password',
              suffixIcon: IconButton(
                icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _show = !_show),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.orangeAccent),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _unlock,
            child: _busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Unlock'),
          ),
          if (biometric) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _fingerprint,
              icon: const Icon(Icons.fingerprint),
              label: const Text('Use fingerprint'),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Unlocked: the list
// ---------------------------------------------------------------------------

enum _Filter { all, favorites, weak, reused }

class _VaultListView extends ConsumerStatefulWidget {
  const _VaultListView();

  @override
  ConsumerState<_VaultListView> createState() => _VaultListViewState();
}

class _VaultListViewState extends ConsumerState<_VaultListView> {
  final _search = TextEditingController();
  _Filter _filter = _Filter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vault = ref.watch(vaultProvider);
    final reused = vault.reusedPasswords;
    bool weak(VaultEntry e) =>
        strengthOf(e.password).index < PasswordStrength.fair.index;
    final weakCount = vault.entries.where(weak).length;
    final reusedCount = vault.entries
        .where((e) => reused.contains(e.password))
        .length;

    final q = _search.text.trim().toLowerCase();
    final shown =
        vault.entries.where((e) {
          final matches =
              q.isEmpty ||
              e.title.toLowerCase().contains(q) ||
              e.username.toLowerCase().contains(q) ||
              e.url.toLowerCase().contains(q);
          return matches &&
              switch (_filter) {
                _Filter.all => true,
                _Filter.favorites => e.favorite,
                _Filter.weak => weak(e),
                _Filter.reused => reused.contains(e.password),
              };
        }).toList()..sort((a, b) {
          if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Passwords'),
        actions: [
          IconButton(
            tooltip: 'Lock',
            icon: const Icon(Icons.lock_outline),
            onPressed: () => ref.read(vaultProvider.notifier).lock(),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(PasswordsRoutes.settings),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search ${vault.entries.length} passwords',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (final (f, label) in [
                  (_Filter.all, 'All'),
                  (_Filter.favorites, 'Favourites'),
                  if (weakCount > 0) (_Filter.weak, 'Weak · $weakCount'),
                  if (reusedCount > 0)
                    (_Filter.reused, 'Reused · $reusedCount'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: vault.entries.isEmpty
                ? const _EmptyVault()
                : ListView.builder(
                    padding: const EdgeInsets.only(top: 6, bottom: 96),
                    itemCount: shown.length,
                    itemBuilder: (context, i) {
                      final e = shown[i];
                      return ListTile(
                        leading: EntryAvatar(
                          label: e.host.isNotEmpty ? e.host : e.title,
                        ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                e.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (e.favorite)
                              const Padding(
                                padding: EdgeInsets.only(left: 6),
                                child: Icon(
                                  Icons.star,
                                  size: 16,
                                  color: Color(0xFFF5C518),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          e.username.isNotEmpty ? e.username : e.host,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white54),
                        ),
                        trailing: IconButton(
                          tooltip: 'Copy password',
                          icon: const Icon(Icons.copy, size: 20),
                          onPressed: () =>
                              copySecret(context, ref, e.password, 'Password'),
                        ),
                        onTap: () => context.push(PasswordsRoutes.entry(e.id)),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add password',
        onPressed: () => context.push(PasswordsRoutes.create),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _EmptyVault extends StatelessWidget {
  const _EmptyVault();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.key, size: 56, color: Colors.white24),
          const SizedBox(height: 12),
          const Text(
            'No passwords yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Add one with +, or import a CSV exported from Chrome or another '
            'password manager (Settings → Import).',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => context.push(PasswordsRoutes.settings),
            icon: const Icon(Icons.upload_file),
            label: const Text('Import CSV'),
          ),
        ],
      ),
    ),
  );
}

/// Copies a secret (cleared from the clipboard after 30 s).
Future<void> copySecret(
  BuildContext context,
  WidgetRef ref,
  String value,
  String what,
) async {
  if (value.isEmpty) return;
  await ref.read(vaultNativeProvider).copy(value);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('$what copied · clears in 30 s'),
        duration: const Duration(seconds: 2),
      ),
    );
}
