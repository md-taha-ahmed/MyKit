import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ai/gemini_client.dart';
import '../../../../core/storage/shared_preferences_provider.dart';
import '../../../backup/presentation/providers/backup_providers.dart';
import '../../../limiter/presentation/providers/limiter_providers.dart';
import '../../../passwords/presentation/providers/vault_providers.dart';
import '../../data/setup_native.dart';

/// Set in `main()`: nothing was saved before this launch.
final freshInstallProvider = Provider<bool>((ref) => false);

final setupNativeProvider = Provider<SetupNative>((ref) => SetupNative());

/// What's set up, checked live (refreshed when MyKit comes back from a
/// system settings screen).
class SetupStatus {
  const SetupStatus({
    this.notifications = false,
    this.battery = false,
    this.ai = false,
    this.backup = false,
    this.screenTime = false,
    this.autofill = false,
    this.passwords = false,
  });

  final bool notifications;
  final bool battery;
  final bool ai;
  final bool backup;
  final bool screenTime;
  final bool autofill;
  final bool passwords;

  /// The recommended items (the rest are optional per tool).
  int get essentialsDone =>
      [notifications, battery, ai, backup].where((d) => d).length;
  static const essentials = 4;
}

final setupStatusProvider =
    AsyncNotifierProvider.autoDispose<SetupStatusNotifier, SetupStatus>(
      SetupStatusNotifier.new,
    );

class SetupStatusNotifier extends AsyncNotifier<SetupStatus> {
  @override
  Future<SetupStatus> build() async {
    final lifecycle = AppLifecycleListener(onResume: refresh);
    ref.onDispose(lifecycle.dispose);
    return _check();
  }

  Future<void> refresh() async {
    state = AsyncData(await _check());
  }

  Future<SetupStatus> _check() async {
    final native = await ref.read(setupNativeProvider).status();
    var notifications = false;
    try {
      notifications =
          await FlutterLocalNotificationsPlugin()
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.areNotificationsEnabled() ??
          false;
    } catch (_) {}
    var screenTime = false;
    try {
      screenTime =
          (await ref.read(limiterNativeProvider).status()).serviceEnabled;
    } catch (_) {}
    return SetupStatus(
      notifications: notifications,
      battery: native.batteryUnrestricted,
      ai: ref.read(geminiClientProvider).isConfigured,
      backup: ref.read(backupServiceProvider).drive.isSignedIn,
      screenTime: screenTime,
      autofill: native.autofill,
      passwords: ref.read(vaultProvider).status != VaultStatus.noVault,
    );
  }
}

/// The checklist was finished or skipped once (shown again from Settings).
final setupDoneProvider = NotifierProvider<SetupDoneNotifier, bool>(
  SetupDoneNotifier.new,
);

class SetupDoneNotifier extends Notifier<bool> {
  static const key = 'setup.done';

  @override
  bool build() => ref.read(sharedPreferencesProvider).getBool(key) ?? false;

  Future<void> markDone() async {
    state = true;
    await ref.read(sharedPreferencesProvider).setBool(key, true);
  }
}
