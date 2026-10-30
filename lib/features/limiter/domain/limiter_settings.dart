import 'package:flutter/material.dart';

/// A platform with one shared daily allowance across its apps and website.
class LimitGroup {
  const LimitGroup({
    required this.id,
    required this.name,
    required this.packages,
    required this.domains,
    required this.limitMinutes,
    this.enabled = true,
  });

  final String id;
  final String name;

  /// Android apps (original, Lite, modded…).
  final List<String> packages;

  /// Websites (subdomains included).
  final List<String> domains;
  final int limitMinutes;
  final bool enabled;

  LimitGroup copyWith({int? limitMinutes, bool? enabled}) => LimitGroup(
    id: id,
    name: name,
    packages: packages,
    domains: domains,
    limitMinutes: limitMinutes ?? this.limitMinutes,
    enabled: enabled ?? this.enabled,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'packages': packages,
    'domains': domains,
    'limitMinutes': limitMinutes,
    'enabled': enabled,
  };

  static LimitGroup fromJson(Map<String, dynamic> j) => LimitGroup(
    id: j['id'] as String,
    name: j['name'] as String,
    packages: (j['packages'] as List).cast<String>(),
    domains: (j['domains'] as List).cast<String>(),
    limitMinutes: (j['limitMinutes'] as num).toInt(),
    enabled: j['enabled'] as bool? ?? true,
  );
}

/// Fully blocked between [start] and [end] (may cross midnight).
class FocusWindow {
  const FocusWindow({
    required this.start,
    required this.end,
    required this.days,
    required this.groups,
  });

  final TimeOfDay start;
  final TimeOfDay end;

  /// 1 = Monday … 7 = Sunday.
  final Set<int> days;
  final Set<String> groups;

  static String _hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static TimeOfDay _parse(String s) {
    final [h, m] = s.split(':').map(int.parse).toList();
    return TimeOfDay(hour: h, minute: m);
  }

  Map<String, dynamic> toJson() => {
    'start': _hhmm(start),
    'end': _hhmm(end),
    'days': [for (final d in days.toList()..sort()) '$d'],
    'groups': groups.toList(),
  };

  static FocusWindow fromJson(Map<String, dynamic> j) => FocusWindow(
    start: _parse(j['start'] as String),
    end: _parse(j['end'] as String),
    days: {for (final d in j['days'] as List) int.parse('$d')},
    groups: (j['groups'] as List).cast<String>().toSet(),
  );

  String get label => '${_hhmm(start)}–${_hhmm(end)}';
}

class LimiterSettings {
  const LimiterSettings({
    required this.groups,
    this.focus = const [],
    this.extensionMinutes = 5,
    this.extensionsPerDay = 2,
    this.extensionWaitSeconds = 15,
    this.warnMinutes = 5,
  });

  final List<LimitGroup> groups;
  final List<FocusWindow> focus;
  final int extensionMinutes;
  final int extensionsPerDay;
  final int extensionWaitSeconds;
  final int warnMinutes;

  /// Instagram, Facebook, X and YouTube: app, Lite / modded apps and site
  /// share one limit. YouTube also counts MyKit's own Shorts player.
  static const defaults = LimiterSettings(
    groups: [
      LimitGroup(
        id: 'instagram',
        name: 'Instagram',
        packages: ['com.instagram.android', 'com.instagram.lite'],
        domains: ['instagram.com'],
        limitMinutes: 30,
      ),
      LimitGroup(
        id: 'facebook',
        name: 'Facebook',
        packages: ['com.facebook.katana', 'com.facebook.lite'],
        domains: ['facebook.com', 'fb.com', 'fb.watch'],
        limitMinutes: 30,
      ),
      LimitGroup(
        id: 'x',
        name: 'X',
        packages: ['com.twitter.android', 'com.twitter.android.lite'],
        domains: ['x.com', 'twitter.com'],
        limitMinutes: 30,
      ),
      LimitGroup(
        id: 'youtube',
        name: 'YouTube',
        packages: [
          'com.google.android.youtube',
          'app.revanced.android.youtube',
          'app.rvx.android.youtube',
        ],
        domains: ['youtube.com', 'youtu.be'],
        limitMinutes: 60,
      ),
    ],
  );

  LimitGroup? group(String id) {
    for (final g in groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  LimiterSettings copyWith({
    List<LimitGroup>? groups,
    List<FocusWindow>? focus,
  }) => LimiterSettings(
    groups: groups ?? this.groups,
    focus: focus ?? this.focus,
    extensionMinutes: extensionMinutes,
    extensionsPerDay: extensionsPerDay,
    extensionWaitSeconds: extensionWaitSeconds,
    warnMinutes: warnMinutes,
  );

  Map<String, dynamic> toJson() => {
    'groups': [for (final g in groups) g.toJson()],
    'focus': [for (final f in focus) f.toJson()],
    'extensionMinutes': extensionMinutes,
    'extensionsPerDay': extensionsPerDay,
    'extensionWaitSeconds': extensionWaitSeconds,
    'warnMinutes': warnMinutes,
  };

  static LimiterSettings fromJson(Map<String, dynamic> j) => LimiterSettings(
    groups: [
      for (final g in j['groups'] as List)
        LimitGroup.fromJson(g as Map<String, dynamic>),
    ],
    focus: [
      for (final f in j['focus'] as List? ?? const [])
        FocusWindow.fromJson(f as Map<String, dynamic>),
    ],
    extensionMinutes: (j['extensionMinutes'] as num?)?.toInt() ?? 5,
    extensionsPerDay: (j['extensionsPerDay'] as num?)?.toInt() ?? 2,
    extensionWaitSeconds: (j['extensionWaitSeconds'] as num?)?.toInt() ?? 15,
    warnMinutes: (j['warnMinutes'] as num?)?.toInt() ?? 5,
  );
}
