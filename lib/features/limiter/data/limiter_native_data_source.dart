import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/limiter_settings.dart';

/// Today's state from the limiter service.
class LimiterStatus {
  const LimiterStatus({
    this.serviceEnabled = false,
    this.usage = const {},
    this.extensionsUsed = const {},
  });

  /// The accessibility service is switched on.
  final bool serviceEnabled;

  /// Seconds per platform, per day ("2026-10-30" → {"instagram": 125}).
  final Map<String, Map<String, int>> usage;

  /// Extensions taken today per platform.
  final Map<String, int> extensionsUsed;

  Map<String, int> day(DateTime d) => usage[_key(d)] ?? const {};

  static String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Android side (`android/.../limiter/`): settings in, usage out.
class LimiterNativeDataSource {
  static const _channel = MethodChannel('com.mdtaha.mykit/limiter');

  Future<void> setConfig(LimiterSettings settings) => _channel.invokeMethod(
    'setConfig',
    {'json': jsonEncode(settings.toJson())},
  );

  Future<LimiterStatus> status() async {
    final raw = await _channel.invokeMapMethod<String, Object?>('status');
    if (raw == null) return const LimiterStatus();
    final usage = jsonDecode(raw['usage'] as String? ?? '{}') as Map;
    final ext = jsonDecode(raw['extensions'] as String? ?? '{}') as Map;
    return LimiterStatus(
      serviceEnabled: raw['enabled'] == true,
      usage: {
        for (final MapEntry(:key, :value) in usage.entries)
          '$key': {
            for (final e in (value as Map).entries)
              '${e.key}': (e.value as num).toInt(),
          },
      },
      extensionsUsed: {
        for (final MapEntry(:key, :value) in ext.entries)
          if (value is Map) '$key': (value['used'] as num?)?.toInt() ?? 0,
      },
    );
  }

  Future<void> openSettings() => _channel.invokeMethod('openSettings');

  /// MyKit's Shorts player is open (counts toward YouTube).
  Future<void> setShortsActive(bool active) async {
    try {
      await _channel.invokeMethod('setShortsActive', {'active': active});
    } catch (_) {
      // Tests / older builds.
    }
  }
}
