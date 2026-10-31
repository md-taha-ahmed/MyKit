import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/widgets/dialogs.dart';
import '../../domain/entities/fitness_entities.dart';
import '../../domain/progress_math.dart';
import '../providers/fitness_providers.dart';

String fmtKg(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// "1 set", "3 sets".
String plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

String fmtDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  return h > 0 ? '${h}h ${m}m' : '${m}m';
}

const weekdayShort = {
  DateTime.saturday: 'Sat',
  DateTime.sunday: 'Sun',
  DateTime.monday: 'Mon',
  DateTime.tuesday: 'Tue',
  DateTime.wednesday: 'Wed',
  DateTime.thursday: 'Thu',
  DateTime.friday: 'Fri',
};

/// Week order starting Saturday.
const weekOrder = [
  DateTime.saturday,
  DateTime.sunday,
  DateTime.monday,
  DateTime.tuesday,
  DateTime.wednesday,
  DateTime.thursday,
  DateTime.friday,
];

class _NumberField extends StatelessWidget {
  const _NumberField(this.controller, this.label, {this.suffix});

  final TextEditingController controller;
  final String label;
  final String? suffix;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
    decoration: InputDecoration(
      labelText: label,
      suffixText: suffix,
      isDense: true,
    ),
  );
}

double? _parse(TextEditingController c) =>
    double.tryParse(c.text.trim().replaceAll(',', '.'));

/// Log weight (and optionally measurements) for a day.
Future<void> showBodyLogSheet(BuildContext context, WidgetRef ref) async {
  final latest = ref.read(bodyLogProvider.notifier).latestWeight;
  final weight = TextEditingController(
    text: latest == null ? '' : fmtKg(latest),
  );
  final measures = {
    for (final k in BodyEntry.measurements) k: TextEditingController(),
  };
  var date = DateTime.now();
  var showMeasures = false;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tr('Log body weight'),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(DateFormat('d MMM').format(date)),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setSheet(() => date = picked);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _NumberField(weight, tr('Weight'), suffix: 'kg'),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Add measurements')),
                subtitle: Text(tr('Waist, chest, arm, hips, thigh (cm)')),
                value: showMeasures,
                onChanged: (v) => setSheet(() => showMeasures = v),
              ),
              if (showMeasures)
                for (final k in BodyEntry.measurements)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _NumberField(
                      measures[k]!,
                      k[0].toUpperCase() + k.substring(1),
                      suffix: 'cm',
                    ),
                  ),
              const SizedBox(height: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: fitnessAccent,
                  foregroundColor: Colors.black,
                ),
                onPressed: () {
                  final w = _parse(weight);
                  final m = {
                    for (final k in measures.keys) k: _parse(measures[k]!),
                  };
                  if (w == null && m.values.every((v) => v == null)) return;
                  ref
                      .read(bodyLogProvider.notifier)
                      .save(
                        BodyEntry(
                          date: date,
                          weightKg: w,
                          waistCm: m['waist'],
                          chestCm: m['chest'],
                          armCm: m['arm'],
                          hipsCm: m['hips'],
                          thighCm: m['thigh'],
                        ),
                      );
                  Navigator.pop(context);
                },
                child: Text(tr('Save')),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  weight.dispose();
  for (final c in measures.values) {
    c.dispose();
  }
}

/// Height, starting weight, goal and reminders.
Future<void> showProfileSheet(BuildContext context, WidgetRef ref) async {
  final p = ref.read(fitnessProfileProvider);
  final height = TextEditingController(text: fmtKg(p.heightCm));
  final start = TextEditingController(text: fmtKg(p.startWeightKg));
  final goal = TextEditingController(text: fmtKg(p.goalWeightKg));
  var reminders = p.remindersOn;
  var minutes = p.reminderMinutes;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) {
        final h = _parse(height) ?? p.heightCm;
        final healthy = ProgressMath.healthyWeight(h);
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr('Profile & goal'),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                _NumberField(height, tr('Height'), suffix: 'cm'),
                const SizedBox(height: 8),
                _NumberField(start, tr('Starting weight'), suffix: 'kg'),
                const SizedBox(height: 8),
                _NumberField(goal, tr('Goal weight'), suffix: 'kg'),
                const SizedBox(height: 4),
                Text(
                  tr(
                    'A healthy BMI (under 25) at {0} cm is up to {1} kg. A first goal of losing 5–10% is a great start.',
                    {'0': fmtKg(h), '1': fmtKg(healthy)},
                  ),
                  style: const TextStyle(fontSize: 12, color: Colors.white60),
                ),
                const Divider(height: 28),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Workout reminders')),
                  subtitle: Text(tr('A notification on your training days')),
                  value: reminders,
                  onChanged: (v) => setSheet(() => reminders = v),
                ),
                if (reminders)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.alarm),
                    title: Text(tr('Remind me at')),
                    trailing: Text(
                      TimeOfDay(
                        hour: minutes ~/ 60,
                        minute: minutes % 60,
                      ).format(context),
                    ),
                    onTap: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(
                          hour: minutes ~/ 60,
                          minute: minutes % 60,
                        ),
                      );
                      if (t != null) {
                        setSheet(() => minutes = t.hour * 60 + t.minute);
                      }
                    },
                  ),
                const SizedBox(height: 12),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: fitnessAccent,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () async {
                    final notifier = ref.read(fitnessProfileProvider.notifier);
                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.pop(context);
                    await notifier.update(
                      p.copyWith(
                        heightCm: _parse(height),
                        startWeightKg: _parse(start),
                        goalWeightKg: _parse(goal),
                        reminderMinutes: minutes,
                      ),
                    );
                    if (reminders != p.remindersOn &&
                        !await notifier.enableReminders(reminders)) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            tr(
                              'Allow notifications for MyKit to get reminders.',
                            ),
                          ),
                        ),
                      );
                    }
                  },
                  child: Text(tr('Save')),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
  height.dispose();
  start.dispose();
  goal.dispose();
}

/// Details of a finished workout, with delete.
Future<void> showSessionSheet(
  BuildContext context,
  WidgetRef ref,
  WorkoutSession s,
) async {
  final library = ref.read(exerciseLibraryProvider).value ?? const {};
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.routineName ?? tr('Workout'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${DateFormat('EEE d MMM, HH:mm').format(s.startedAt)} · '
                      '${fmtDuration(s.duration)} · ${plural(s.setCount, 'set')}'
                      '${s.volume > 0 ? ' · ${fmtKg(s.volume)} kg lifted' : ''}',
                      style: const TextStyle(color: Colors.white60),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: tr('Delete workout'),
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  final ok = await showConfirmDialog(
                    context,
                    title: tr('Delete this workout?'),
                    message: tr('It disappears from your history and records.'),
                  );
                  if (ok && context.mounted) {
                    await ref.read(sessionsProvider.notifier).remove(s.id);
                    if (context.mounted) Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final e in s.exercises) ...[
            Text(
              library[e.exerciseId]?.name ?? e.exerciseId.replaceAll('_', ' '),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              [
                for (final x in e.sets)
                  x.seconds > 0
                      ? '${x.seconds}s'
                      : x.weightKg > 0
                      ? '${fmtKg(x.weightKg)}×${x.reps}'
                      : '${x.reps}',
              ].join('   '),
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    ),
  );
}
