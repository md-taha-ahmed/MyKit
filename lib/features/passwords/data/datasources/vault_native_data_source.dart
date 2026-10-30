import 'package:flutter/services.dart';

/// Result of a fingerprint prompt.
enum BiometricOutcome { success, cancelled, invalidated, failed }

/// Android side of the Passwords tool (`android/.../vault/VaultChannel.kt`):
/// fingerprint-protected copy of the vault key, FLAG_SECURE and a
/// self-clearing, sensitive clipboard.
class VaultNativeDataSource {
  static const _channel = MethodChannel('com.mdtaha.mykit/vault');

  Future<bool> biometricAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('biometricAvailable') ?? false;
    } catch (_) {
      return false; // no plugin (tests) or no biometric hardware
    }
  }

  Future<bool> hasBiometricKey() async {
    try {
      return await _channel.invokeMethod<bool>('hasBiometricKey') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Stores [vaultKey] behind a fingerprint check (prompts once).
  Future<BiometricOutcome> enrollBiometric(Uint8List vaultKey) async {
    try {
      await _channel.invokeMethod<bool>('enrollBiometric', {
        'secret': vaultKey,
      });
      return BiometricOutcome.success;
    } on PlatformException catch (e) {
      return _outcome(e);
    }
  }

  /// The vault key after a fingerprint check, or why there isn't one.
  Future<(BiometricOutcome, Uint8List?)> unlockBiometric() async {
    try {
      final key = await _channel.invokeMethod<Uint8List>('unlockBiometric');
      return (BiometricOutcome.success, key);
    } on PlatformException catch (e) {
      return (_outcome(e), null);
    }
  }

  Future<void> removeBiometric() => _channel.invokeMethod('removeBiometric');

  /// Blocks screenshots and the recent-apps preview while the vault is open.
  Future<void> setSecure(bool on) async {
    try {
      await _channel.invokeMethod('setSecure', {'on': on});
    } on MissingPluginException {
      // Tests / other platforms.
    }
  }

  /// Copies [text] marked as sensitive; it's cleared after [clearAfter].
  Future<void> copy(
    String text, {
    Duration clearAfter = const Duration(seconds: 30),
  }) => _channel.invokeMethod('copySensitive', {
    'text': text,
    'clearAfterMs': clearAfter.inMilliseconds,
  });

  /// MyKit (or any app) is the phone's autofill service.
  Future<bool> autofillEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('autofillEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens Android's "choose autofill service" screen for MyKit.
  Future<bool> openAutofillSettings() async =>
      await _channel.invokeMethod<bool>('openAutofillSettings') ?? false;

  /// Forgets which logins were used in which apps.
  Future<void> clearAutofillLinks() =>
      _channel.invokeMethod('clearAutofillLinks');

  static BiometricOutcome _outcome(PlatformException e) => switch (e.code) {
    'cancelled' => BiometricOutcome.cancelled,
    'invalidated' || 'missing' => BiometricOutcome.invalidated,
    _ => BiometricOutcome.failed,
  };
}
