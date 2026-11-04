import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/storage/shared_preferences_provider.dart';
import '../../data/limiter_native_data_source.dart';
import '../../domain/limiter_settings.dart';

const limiterAccent = Color(0xFF26C6DA);

final limiterNativeProvider = Provider<LimiterNativeDataSource>(
  (ref) => LimiterNativeDataSource(),
);

/// The limits and focus hours. Saved in MyKit (so they're backed up) and
/// handed to the Android service, which enforces them.
final limiterSettingsProvider =
    NotifierProvider<LimiterSettingsNotifier, LimiterSettings>(
      LimiterSettingsNotifier.new,
    );

class LimiterSettingsNotifier extends Notifier<LimiterSettings> {
  static const _key = 'limiter.settings.v1';

  @override
  LimiterSettings build() {
    final raw = ref.read(sharedPreferencesProvider).getString(_key);
    var settings = LimiterSettings.defaults;
    if (raw != null) {
      try {
        settings = LimiterSettings.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } catch (_) {}
    }
    // The service keeps its own copy; make sure it's current.
    ref.read(limiterNativeProvider).setConfig(settings).ignore();
    return settings;
  }

  Future<void> _save(LimiterSettings s) async {
    state = s;
    await ref
        .read(sharedPreferencesProvider)
        .setString(_key, jsonEncode(s.toJson()));
    await ref.read(limiterNativeProvider).setConfig(s);
  }

  Future<void> updateGroup(LimitGroup group) => _save(
    state.copyWith(
      groups: [for (final g in state.groups) g.id == group.id ? group : g],
    ),
  );

  Future<void> addFocus(FocusWindow f) =>
      _save(state.copyWith(focus: [...state.focus, f]));

  Future<void> removeFocus(int index) =>
      _save(state.copyWith(focus: [...state.focus]..removeAt(index)));
}

/// Today's and this week's usage, refreshed every 15 s while watched and
/// when MyKit comes back to the front.
final limiterStatusProvider =
    NotifierProvider.autoDispose<LimiterStatusNotifier, LimiterStatus>(
      LimiterStatusNotifier.new,
    );

class LimiterStatusNotifier extends Notifier<LimiterStatus> {
  @override
  LimiterStatus build() {
    final timer = Timer.periodic(const Duration(seconds: 15), (_) => refresh());
    final lifecycle = AppLifecycleListener(onResume: refresh);
    ref.onDispose(() {
      timer.cancel();
      lifecycle.dispose();
    });
    Future.microtask(refresh);
    return const LimiterStatus();
  }

  Future<void> refresh() async {
    try {
      state = await ref.read(limiterNativeProvider).status();
    } catch (_) {}
  }
}

/// "1 h 05 min" / "12 min" / "< 1 min".
String formatMinutes(int seconds) {
  final m = seconds ~/ 60;
  if (m < 1) return seconds > 0 ? tr('< 1 min') : tr('0 min');
  if (m < 60) return tr('{m} min', {'m': m});
  return tr('{h} h {m} min', {
    'h': m ~/ 60,
    'm': (m % 60).toString().padLeft(2, '0'),
  });
}
