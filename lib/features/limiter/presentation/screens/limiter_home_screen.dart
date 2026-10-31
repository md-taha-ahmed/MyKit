import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/i18n/i18n.dart';
import '../../data/limiter_native_data_source.dart';
import '../../domain/limiter_settings.dart';
import '../providers/limiter_providers.dart';

/// Platform colours for cards and the weekly chart.
const _groupColors = {
  'instagram': Color(0xFFE1306C),
  'facebook': Color(0xFF1877F2),
  'x': Color(0xFFB0B3BA),
  'youtube': Color(0xFFFF3B30),
};

Color _colorOf(String id) => _groupColors[id] ?? limiterAccent;

class LimiterHomeScreen extends ConsumerWidget {
  const LimiterHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(limiterSettingsProvider);
    final status = ref.watch(limiterStatusProvider);
    final today = status.day(DateTime.now());
    final total = settings.groups.fold<int>(
      0,
      (sum, g) => sum + (today[g.id] ?? 0),
    );

    return Scaffold(
      appBar: AppBar(title: Text(tr('Screen time'))),
      body: RefreshIndicator(
        onRefresh: ref.read(limiterStatusProvider.notifier).refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            if (!status.serviceEnabled) const _SetupCard(),
            const SizedBox(height: 8),
            Text(tr('Today'), style: Theme.of(context).textTheme.titleMedium),
            Text(
              formatMinutes(total),
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            for (final g in settings.groups)
              _GroupCard(
                group: g,
                seconds: today[g.id] ?? 0,
                extensionsUsed: status.extensionsUsed[g.id] ?? 0,
                extensionsPerDay: settings.extensionsPerDay,
              ),
            const SizedBox(height: 20),
            Text(
              tr('This week'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            _WeekChart(settings: settings, status: status),
            const SizedBox(height: 24),
            const _FocusSection(),
            const SizedBox(height: 16),
            Text(
              tr(
                'When a limit is reached the app or site is closed. You can take {extensionMinutes} more minutes after a {extensionWaitSeconds}-second wait, {extensionsPerDay}× a day per platform (not during focus hours). A notification warns you {warnMinutes} minutes before.',
                {
                  'extensionMinutes': settings.extensionMinutes,
                  'extensionWaitSeconds': settings.extensionWaitSeconds,
                  'extensionsPerDay': settings.extensionsPerDay,
                  'warnMinutes': settings.warnMinutes,
                },
              ),
              style: const TextStyle(color: Colors.white54, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetupCard extends ConsumerWidget {
  const _SetupCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
    color: limiterAccent.withValues(alpha: 0.10),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.accessibility_new, color: limiterAccent),
              SizedBox(width: 10),
              Text(
                tr('Turn on Screen time'),
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              'MyKit needs Android\'s Accessibility permission to see which app is open (and the site in your browser\'s address bar) so it can count your time and close apps when you hit a limit. Nothing leaves your phone.\n\nIn the list, open "Installed apps" (or "Downloaded apps") → MyKit Screen time → turn it on.',
            ),
            style: TextStyle(height: 1.4),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => ref.read(limiterNativeProvider).openSettings(),
            icon: const Icon(Icons.open_in_new),
            label: Text(tr('Open Accessibility settings')),
          ),
        ],
      ),
    ),
  );
}

class _GroupCard extends ConsumerWidget {
  const _GroupCard({
    required this.group,
    required this.seconds,
    required this.extensionsUsed,
    required this.extensionsPerDay,
  });

  final LimitGroup group;
  final int seconds;
  final int extensionsUsed;
  final int extensionsPerDay;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    var limit = group.limitMinutes;
    var enabled = group.enabled;
    final save = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(group.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                {...group.packages.map(_appName), ...group.domains}.join(' · '),
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Limit this')),
                value: enabled,
                onChanged: (v) => setState(() => enabled = v),
              ),
              Text(tr('Daily limit: {0}', {'0': formatMinutes(limit * 60)})),
              Slider(
                value: limit.toDouble(),
                min: 5,
                max: 180,
                divisions: 35,
                label: formatMinutes(limit * 60),
                onChanged: enabled
                    ? (v) => setState(() => limit = v.round())
                    : null,
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(tr('Save')),
              ),
            ],
          ),
        ),
      ),
    );
    if (save == true) {
      await ref
          .read(limiterSettingsProvider.notifier)
          .updateGroup(group.copyWith(limitMinutes: limit, enabled: enabled));
    }
  }

  static String _appName(String pkg) => switch (pkg) {
    'com.instagram.android' => tr('Instagram app'),
    'com.instagram.lite' => tr('Instagram Lite'),
    'com.facebook.katana' => tr('Facebook app'),
    'com.facebook.lite' => tr('Facebook Lite'),
    'com.twitter.android' => tr('X app'),
    'com.twitter.android.lite' => tr('X Lite'),
    'com.google.android.youtube' => tr('YouTube app'),
    'app.revanced.android.youtube' ||
    'app.rvx.android.youtube' => tr('ReVanced'),
    _ => pkg,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _colorOf(group.id);
    final limit = group.limitMinutes * 60;
    final progress = limit == 0 ? 0.0 : (seconds / limit).clamp(0.0, 1.0);
    final over = seconds >= limit;
    final left = limit - seconds;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _edit(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: color.withValues(alpha: 0.2),
                    child: Text(
                      group.name[0],
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      group.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    group.enabled
                        ? '${formatMinutes(seconds)} / ${formatMinutes(limit)}'
                        : tr('{0} · no limit', {'0': formatMinutes(seconds)}),
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
              if (group.enabled) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    color: over ? Colors.redAccent : color,
                    backgroundColor: Colors.white10,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    over ? tr('Limit reached') : '${formatMinutes(left)} left',
                    if (extensionsUsed > 0)
                      '$extensionsUsed/$extensionsPerDay extensions used',
                  ].join(' · '),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: over ? Colors.redAccent : Colors.white54,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Stacked bars: minutes per day for the last 7 days, by platform.
class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.settings, required this.status});

  final LimiterSettings settings;
  final LimiterStatus status;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final days = [
      for (var i = 6; i >= 0; i--) DateTime(now.year, now.month, now.day - i),
    ];
    final totals = [
      for (final d in days)
        settings.groups.fold<int>(0, (s, g) => s + (status.day(d)[g.id] ?? 0)),
    ];
    final maxSeconds = totals.fold<int>(60 * 30, (a, b) => a > b ? a : b);
    final avg = totals.reduce((a, b) => a + b) ~/ 7;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 150,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (i, d) in days.indexed)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (totals[i] > 0)
                          Text(
                            '${totals[i] ~/ 60}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white54,
                            ),
                          ),
                        const SizedBox(height: 3),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: Column(
                            children: [
                              for (final g in settings.groups.reversed)
                                if ((status.day(d)[g.id] ?? 0) > 0)
                                  Container(
                                    height:
                                        110 *
                                        (status.day(d)[g.id]! / maxSeconds),
                                    color: _colorOf(g.id),
                                  ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          DateFormat('E').format(d).substring(0, 2),
                          style: TextStyle(
                            fontSize: 12,
                            color: i == 6 ? Colors.white : Colors.white54,
                            fontWeight: i == 6 ? FontWeight.w700 : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(
              tr('Daily average {0}', {'0': formatMinutes(avg)}),
              style: const TextStyle(color: Colors.white70),
            ),
            for (final g in settings.groups)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _colorOf(g.id),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(g.name, style: const TextStyle(fontSize: 12.5)),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _FocusSection extends ConsumerWidget {
  const _FocusSection();

  static const _dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final groups = ref.read(limiterSettingsProvider).groups;
    var start = const TimeOfDay(hour: 23, minute: 0);
    var end = const TimeOfDay(hour: 7, minute: 0);
    final days = {1, 2, 3, 4, 5, 6, 7};
    final chosen = {for (final g in groups) g.id};
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr('Focus hours'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                tr('These are fully blocked at this time, no extensions.'),
                style: TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: start,
                        );
                        if (t != null) setState(() => start = t);
                      },
                      child: Text(tr('From {0}', {'0': start.format(context)})),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: end,
                        );
                        if (t != null) setState(() => end = t);
                      },
                      child: Text(tr('To {0}', {'0': end.format(context)})),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                children: [
                  for (var d = 1; d <= 7; d++)
                    FilterChip(
                      label: Text(_dayLetters[d - 1]),
                      selected: days.contains(d),
                      onSelected: (on) =>
                          setState(() => on ? days.add(d) : days.remove(d)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  for (final g in groups)
                    FilterChip(
                      label: Text(g.name),
                      selected: chosen.contains(g.id),
                      onSelected: (on) => setState(
                        () => on ? chosen.add(g.id) : chosen.remove(g.id),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: days.isEmpty || chosen.isEmpty
                    ? null
                    : () => Navigator.pop(context, true),
                child: Text(tr('Add')),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true) {
      await ref
          .read(limiterSettingsProvider.notifier)
          .addFocus(
            FocusWindow(start: start, end: end, days: days, groups: chosen),
          );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(limiterSettingsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                tr('Focus hours'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton.icon(
              onPressed: () => _add(context, ref),
              icon: const Icon(Icons.add),
              label: Text(tr('Add')),
            ),
          ],
        ),
        if (settings.focus.isEmpty)
          Text(
            tr(
              'None. Add times when these apps are off completely, e.g. 23:00–07:00 for better sleep.',
            ),
            style: TextStyle(color: Colors.white54),
          ),
        for (final (i, f) in settings.focus.indexed)
          Card(
            child: ListTile(
              leading: const Icon(Icons.bedtime_outlined),
              title: Text(f.label),
              subtitle: Text(
                [
                  f.days.length == 7
                      ? tr('Every day')
                      : (f.days.toList()..sort())
                            .map((d) => _dayLetters[d - 1])
                            .join(' '),
                  settings.groups
                      .where((g) => f.groups.contains(g.id))
                      .map((g) => g.name)
                      .join(', '),
                ].join(' · '),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () =>
                    ref.read(limiterSettingsProvider.notifier).removeFocus(i),
              ),
            ),
          ),
      ],
    );
  }
}
