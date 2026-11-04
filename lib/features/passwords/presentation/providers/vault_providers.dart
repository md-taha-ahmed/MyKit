import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/storage/shared_preferences_provider.dart';
import '../../data/datasources/vault_native_data_source.dart';
import '../../data/services/vault_crypto.dart';
import '../../domain/entities/vault_entry.dart';
import '../../domain/services/vault_csv.dart';

const passwordsAccent = Color(0xFFE85D9A);

final vaultNativeProvider = Provider<VaultNativeDataSource>(
  (ref) => VaultNativeDataSource(),
);

enum VaultStatus { noVault, locked, unlocked }

class VaultState {
  const VaultState({
    required this.status,
    this.entries = const [],
    this.biometricAvailable = false,
    this.biometricEnabled = false,
    this.autoLock = const Duration(minutes: 1),
  });

  final VaultStatus status;

  /// Decrypted entries; only in memory, and only while unlocked.
  final List<VaultEntry> entries;
  final bool biometricAvailable;
  final bool biometricEnabled;

  /// Locks after the app has been in the background this long.
  final Duration autoLock;

  VaultEntry? byId(String id) {
    for (final e in entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Passwords used by more than one entry.
  Set<String> get reusedPasswords {
    final seen = <String>{}, reused = <String>{};
    for (final e in entries) {
      if (e.password.isNotEmpty && !seen.add(e.password)) {
        reused.add(e.password);
      }
    }
    return reused;
  }

  VaultState copyWith({
    VaultStatus? status,
    List<VaultEntry>? entries,
    bool? biometricAvailable,
    bool? biometricEnabled,
    Duration? autoLock,
  }) => VaultState(
    status: status ?? this.status,
    entries: entries ?? this.entries,
    biometricAvailable: biometricAvailable ?? this.biometricAvailable,
    biometricEnabled: biometricEnabled ?? this.biometricEnabled,
    autoLock: autoLock ?? this.autoLock,
  );
}

final vaultProvider = NotifierProvider<VaultNotifier, VaultState>(
  VaultNotifier.new,
);

class VaultNotifier extends Notifier<VaultState> {
  static const _vaultKey = 'vault.v1';
  static const _autoLockKey = 'vault.autoLockSeconds';
  static const _uuid = Uuid();

  SealedVault? _sealed;

  /// The vault key while unlocked; overwritten on lock.
  Uint8List? _key;

  DateTime? _hiddenAt;

  /// Our own excursions (file picker, fingerprint prompt) don't lock.
  int _holdLock = 0;

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);
  VaultNativeDataSource get _native => ref.read(vaultNativeProvider);

  @override
  VaultState build() {
    final raw = _prefs.getString(_vaultKey);
    _sealed = raw == null ? null : SealedVault.decode(raw);
    final listener = AppLifecycleListener(
      onHide: () => _hiddenAt = DateTime.now(),
      onShow: _maybeAutoLock,
    );
    ref.onDispose(() {
      listener.dispose();
      _wipeKey();
    });
    Future.microtask(_loadBiometricState);
    return VaultState(
      status: _sealed == null ? VaultStatus.noVault : VaultStatus.locked,
      autoLock: Duration(seconds: _prefs.getInt(_autoLockKey) ?? 60),
    );
  }

  Future<void> _loadBiometricState() async {
    final available = await _native.biometricAvailable();
    final enabled = available && await _native.hasBiometricKey();
    state = state.copyWith(
      biometricAvailable: available,
      biometricEnabled: enabled,
    );
  }

  void _maybeAutoLock() {
    final hidden = _hiddenAt;
    _hiddenAt = null;
    if (hidden == null || _holdLock > 0) return;
    if (state.status == VaultStatus.unlocked &&
        DateTime.now().difference(hidden) >= state.autoLock) {
      lock();
    }
  }

  /// Runs [action] (which may leave the app) without auto-locking.
  Future<T> withoutAutoLock<T>(Future<T> Function() action) async {
    _holdLock++;
    try {
      return await action();
    } finally {
      _holdLock--;
      _hiddenAt = null;
    }
  }

  // --- Create / unlock / lock -------------------------------------------

  Future<void> create(String masterPassword) async {
    final salt = VaultCrypto.randomBytes(16);
    const kdf = KdfParams.recommended;
    final kek = await VaultCrypto.deriveKey(masterPassword, salt, kdf);
    final vaultKey = VaultCrypto.newVaultKey();
    final sealed = await VaultCrypto.seal(
      vaultKey: vaultKey,
      kek: kek,
      salt: salt,
      kdf: kdf,
      entriesJson: '[]',
    );
    await _store(sealed);
    _key = vaultKey;
    state = state.copyWith(status: VaultStatus.unlocked, entries: const []);
  }

  /// Throws [VaultException] ("Wrong master password.").
  Future<void> unlockWithPassword(String masterPassword) async {
    final sealed = _sealed;
    if (sealed == null) return;
    final kek = await VaultCrypto.deriveKey(
      masterPassword,
      sealed.salt,
      sealed.kdf,
    );
    await _open(await VaultCrypto.unwrapKey(sealed, kek));
  }

  /// Returns a message when it didn't work (null on success or cancel).
  Future<String?> unlockWithBiometric() async {
    if (_sealed == null) return null;
    final (outcome, key) = await withoutAutoLock(_native.unlockBiometric);
    switch (outcome) {
      case BiometricOutcome.success:
        try {
          await _open(key!);
          return null;
        } on VaultException {
          // The vault was replaced (e.g. restored); the old key can't open it.
          await _native.removeBiometric();
          state = state.copyWith(biometricEnabled: false);
          return tr(
            'Fingerprint unlock needs to be set up again. Use your master password.',
          );
        }
      case BiometricOutcome.cancelled:
        return null;
      case BiometricOutcome.invalidated:
        state = state.copyWith(biometricEnabled: false);
        return tr(
          'Your fingerprints changed, so fingerprint unlock was turned off. Use your master password.',
        );
      case BiometricOutcome.failed:
        return tr('Fingerprint unlock failed. Use your master password.');
    }
  }

  Future<void> _open(Uint8List vaultKey) async {
    final json = await VaultCrypto.open(_sealed!, vaultKey);
    final entries = [
      for (final e in jsonDecode(json) as List)
        VaultEntry.fromJson(e as Map<String, dynamic>),
    ];
    _key = vaultKey;
    state = state.copyWith(status: VaultStatus.unlocked, entries: entries);
  }

  void lock() {
    if (state.status != VaultStatus.unlocked) return;
    _wipeKey();
    state = state.copyWith(status: VaultStatus.locked, entries: const []);
  }

  void _wipeKey() {
    final key = _key;
    if (key != null) key.fillRange(0, key.length, 0);
    _key = null;
  }

  // --- Entries ----------------------------------------------------------

  Future<void> _save(List<VaultEntry> entries) async {
    final key = _key;
    if (key == null || _sealed == null) {
      throw VaultException(tr('The vault is locked.'));
    }
    final sorted = [...entries]
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    await _store(
      await VaultCrypto.reseal(
        _sealed!,
        key,
        jsonEncode([for (final e in sorted) e.toJson()]),
      ),
    );
    state = state.copyWith(entries: sorted);
  }

  Future<void> _store(SealedVault sealed) async {
    _sealed = sealed;
    await _prefs.setString(_vaultKey, sealed.encode());
  }

  Future<VaultEntry> add({
    required String title,
    String username = '',
    String password = '',
    String url = '',
    String notes = '',
  }) async {
    final now = DateTime.now();
    final entry = VaultEntry(
      id: _uuid.v4(),
      title: title.trim(),
      username: username.trim(),
      password: password,
      url: url.trim(),
      notes: notes.trim(),
      createdAt: now,
      updatedAt: now,
      passwordChangedAt: now,
    );
    await _save([...state.entries, entry]);
    return entry;
  }

  Future<void> update(VaultEntry entry) =>
      _save([for (final e in state.entries) e.id == entry.id ? entry : e]);

  Future<void> delete(String id) =>
      _save(state.entries.where((e) => e.id != id).toList());

  Future<void> toggleFavorite(String id) => _save([
    for (final e in state.entries)
      e.id == id
          ? e.copyWith(favorite: !e.favorite, updatedAt: e.updatedAt)
          : e,
  ]);

  // --- Settings ---------------------------------------------------------

  Future<void> setAutoLock(Duration d) async {
    await _prefs.setInt(_autoLockKey, d.inSeconds);
    state = state.copyWith(autoLock: d);
  }

  /// Returns a message if it didn't work.
  Future<String?> enableBiometric() async {
    final key = _key;
    if (key == null) return tr('Unlock the vault first.');
    final outcome = await withoutAutoLock(
      () => _native.enrollBiometric(Uint8List.fromList(key)),
    );
    if (outcome == BiometricOutcome.success) {
      state = state.copyWith(biometricEnabled: true);
      return null;
    }
    return outcome == BiometricOutcome.cancelled
        ? null
        : tr('Could not turn on fingerprint unlock.');
  }

  Future<void> disableBiometric() async {
    await _native.removeBiometric();
    state = state.copyWith(biometricEnabled: false);
  }

  /// Throws [VaultException] if [current] is wrong.
  Future<void> changeMasterPassword(String current, String next) async {
    final sealed = _sealed;
    final key = _key;
    if (sealed == null || key == null) {
      throw VaultException(tr('Unlock the vault first.'));
    }
    // Check the current password before replacing it.
    await VaultCrypto.unwrapKey(
      sealed,
      await VaultCrypto.deriveKey(current, sealed.salt, sealed.kdf),
    );
    final salt = VaultCrypto.randomBytes(16);
    const kdf = KdfParams.recommended;
    await _store(
      await VaultCrypto.seal(
        vaultKey: key,
        kek: await VaultCrypto.deriveKey(next, salt, kdf),
        salt: salt,
        kdf: kdf,
        entriesJson: await VaultCrypto.open(sealed, key),
      ),
    );
  }

  /// Deletes the vault and everything in it. Throws [VaultException] if
  /// [masterPassword] is wrong.
  Future<void> deleteVault(String masterPassword) async {
    final sealed = _sealed;
    if (sealed == null) return;
    await VaultCrypto.unwrapKey(
      sealed,
      await VaultCrypto.deriveKey(masterPassword, sealed.salt, sealed.kdf),
    );
    await _prefs.remove(_vaultKey);
    await _native.removeBiometric();
    _sealed = null;
    _wipeKey();
    state = state.copyWith(
      status: VaultStatus.noVault,
      entries: const [],
      biometricEnabled: false,
    );
  }

  // --- CSV --------------------------------------------------------------

  /// Adds the logins in [csv], skipping ones already saved. Returns
  /// (added, skipped). Throws [FormatException] for unreadable files.
  Future<(int, int)> importCsv(String csv) async {
    final logins = VaultCsv.parse(csv);
    String fingerprint(String url, String title, String user, String pass) =>
        '${_site(url, title)}\u0000${user.toLowerCase()}\u0000$pass';
    final existing = {
      for (final e in state.entries)
        fingerprint(e.url, e.title, e.username, e.password),
    };
    final now = DateTime.now();
    final added = <VaultEntry>[];
    for (final l in logins) {
      if (!existing.add(fingerprint(l.url, l.title, l.username, l.password))) {
        continue;
      }
      added.add(
        VaultEntry(
          id: _uuid.v4(),
          title: l.title.isEmpty ? tr('Untitled') : l.title,
          username: l.username,
          password: l.password,
          url: l.url,
          notes: l.notes,
          createdAt: now,
          updatedAt: now,
          passwordChangedAt: now,
        ),
      );
    }
    if (added.isNotEmpty) await _save([...state.entries, ...added]);
    return (added.length, logins.length - added.length);
  }

  String exportCsv() => VaultCsv.export(state.entries);

  static String _site(String url, String title) {
    final raw = url.trim();
    if (raw.isEmpty) return title.trim().toLowerCase();
    final host =
        Uri.tryParse(raw.contains('://') ? raw : 'https://$raw')?.host ?? raw;
    return host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
  }
}
