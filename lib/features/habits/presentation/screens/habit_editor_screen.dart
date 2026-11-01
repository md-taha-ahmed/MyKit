import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/i18n.dart';
import '../../domain/habit_models.dart';
import '../providers/habit_providers.dart';
import '../widgets/habit_widgets.dart';

/// Creating (or editing) a quest, step by step — each step says why it
/// matters: who you're becoming, a tiny and a full version, the anchor, the
/// obstacles and their if–then plans.
class HabitEditorScreen extends ConsumerStatefulWidget {
  const HabitEditorScreen({super.key, this.habitId});

  final String? habitId;

  @override
  ConsumerState<HabitEditorScreen> createState() => _HabitEditorScreenState();
}

class _HabitEditorScreenState extends ConsumerState<HabitEditorScreen> {
  late final Habit? _old = widget.habitId == null
      ? null
      : ref.read(habitsProvider).habit(widget.habitId!);

  late final _name = TextEditingController(text: _old?.name);
  late final _identity = TextEditingController(text: _old?.identity);
  late final _outcome = TextEditingController(text: _old?.outcome);
  late final _full = TextEditingController(text: _old?.full);
  late final _tiny = TextEditingController(text: _old?.tiny);
  late final _anchor = TextEditingController(text: _old?.anchor);
  late final _pairing = TextEditingController(text: _old?.pairing);
  late HabitStat _stat = _old?.stat ?? HabitStat.discipline;
  late Set<int> _days = {
    ...(_old?.weekdays ?? {1, 2, 3, 4, 5, 6, 7}),
  };
  late int? _reminder = _old == null ? 8 * 60 : _old.reminderMinutes;
  late final List<IfThen> _obstacles = [...?_old?.obstacles];
  late bool _workout = _old?.link == 'fitness';

  static const _weekdays = [6, 7, 1, 2, 3, 4, 5];

  @override
  void dispose() {
    for (final c in [
      _name,
      _identity,
      _outcome,
      _full,
      _tiny,
      _anchor,
      _pairing,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty &&
      _tiny.text.trim().isNotEmpty &&
      _full.text.trim().isNotEmpty &&
      _days.isNotEmpty;

  Future<void> _save() async {
    final notifier = ref.read(habitsProvider.notifier);
    final h = Habit(
      id: _old?.id ?? HabitsNotifier.newId(),
      name: _name.text.trim(),
      stat: _stat,
      identity: _identity.text.trim(),
      outcome: _outcome.text.trim(),
      full: _full.text.trim(),
      tiny: _tiny.text.trim(),
      anchor: _anchor.text.trim(),
      weekdays: _days,
      reminderMinutes: _reminder,
      obstacles: _obstacles,
      pairing: _pairing.text.trim(),
      link: _workout ? 'fitness' : null,
      createdAt: _old?.createdAt ?? DateTime.now(),
      archived: _old?.archived ?? false,
    );
    if (_reminder != null) {
      await ref.read(habitNotificationsProvider).requestPermission();
    }
    await notifier.save(h);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final anchors = [
      tr('Fajr prayer'),
      tr('Dhuhr prayer'),
      tr('Asr prayer'),
      tr('Maghrib prayer'),
      tr('Isha prayer'),
      tr('waking up'),
      tr('breakfast'),
      tr('lunch'),
      tr('getting home'),
      tr('brushing my teeth at night'),
    ];
    final weekdayNames = {
      6: tr('Sat'),
      7: tr('Sun'),
      1: tr('Mon'),
      2: tr('Tue'),
      3: tr('Wed'),
      4: tr('Thu'),
      5: tr('Fri'),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(_old == null ? tr('New quest') : tr('Edit quest')),
        actions: [
          TextButton(onPressed: _valid ? _save : null, child: Text(tr('Save'))),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
        children: [
          _Step(
            n: 1,
            title: tr('The habit'),
            why: tr('One clear action. You can add more quests later.'),
            child: Column(
              children: [
                TextField(
                  controller: _name,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: tr('Name'),
                    hintText: tr('e.g. Read Quran, Workout, Study English'),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final s in HabitStat.values)
                      ChoiceChip(
                        label: Text(statLabel(s)),
                        selected: _stat == s,
                        onSelected: (_) => setState(() => _stat = s),
                      ),
                  ],
                ),
              ],
            ),
          ),
          _Step(
            n: 2,
            title: tr('Who you are becoming'),
            why: tr(
              'Habits last longer when they\'re part of who you are, not just a task. And picturing what you\'ll gain keeps you going on hard days.',
            ),
            child: Column(
              children: [
                TextField(
                  controller: _identity,
                  decoration: InputDecoration(
                    labelText: tr('I\'m someone who…'),
                    hintText: tr('…keeps my body strong whatever happens'),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _outcome,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: tr('What will it bring you?'),
                  ),
                ),
              ],
            ),
          ),
          _Step(
            n: 3,
            title: tr('Full and tiny versions'),
            why: tr(
              'The tiny version takes 2 minutes and still counts. On bad days it keeps the habit alive — showing up matters more than size while it forms.',
            ),
            child: Column(
              children: [
                TextField(
                  controller: _full,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: tr('Full version'),
                    hintText: tr('e.g. Read 10 pages'),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _tiny,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: tr('Tiny version (2 minutes)'),
                    hintText: tr('e.g. Read 1 page'),
                  ),
                ),
              ],
            ),
          ),
          _Step(
            n: 4,
            title: tr('Anchor: after what?'),
            why: tr(
              '"After X, I will Y" plans roughly double follow-through. Pick something you already do every day — prayers stay stable even when everything else changes.',
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _anchor,
                  decoration: InputDecoration(
                    labelText: tr('After…'),
                    hintText: tr('e.g. Fajr prayer'),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final a in anchors)
                      ActionChip(
                        label: Text(a),
                        onPressed: () => setState(() => _anchor.text = a),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final d in _weekdays)
                      FilterChip(
                        label: Text(weekdayNames[d]!),
                        selected: _days.contains(d),
                        onSelected: (on) => setState(() {
                          _days = {..._days};
                          on ? _days.add(d) : _days.remove(d);
                        }),
                      ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Reminder')),
                  subtitle: Text(
                    _reminder == null
                        ? tr('Off')
                        : TimeOfDay(
                            hour: _reminder! ~/ 60,
                            minute: _reminder! % 60,
                          ).format(context),
                  ),
                  value: _reminder != null,
                  onChanged: (on) =>
                      setState(() => _reminder = on ? 8 * 60 : null),
                ),
                if (_reminder != null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: () async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay(
                            hour: _reminder! ~/ 60,
                            minute: _reminder! % 60,
                          ),
                        );
                        if (t != null) {
                          setState(() => _reminder = t.hour * 60 + t.minute);
                        }
                      },
                      child: Text(tr('Change time')),
                    ),
                  ),
              ],
            ),
          ),
          _Step(
            n: 5,
            title: tr('What will get in the way?'),
            why: tr(
              'Picture the real obstacle, then decide now what you\'ll do when it happens: "If …, then I will …". The System adds more as it learns.',
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, o) in _obstacles.indexed)
                  Card(
                    child: ListTile(
                      title: Text(tr('If {when}', {'when': o.when})),
                      subtitle: Text(tr('then {then}', {'then': o.then})),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _obstacles.removeAt(i)),
                      ),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final o = await _askIfThen(context);
                    if (o != null) setState(() => _obstacles.add(o));
                  },
                  icon: const Icon(Icons.add),
                  label: Text(tr('Add an if–then plan')),
                ),
              ],
            ),
          ),
          _Step(
            n: 6,
            title: tr('Make it easier (optional)'),
            why: tr(
              'Pair it with something you enjoy, only during the habit — like a podcast you only hear while walking.',
            ),
            child: Column(
              children: [
                TextField(
                  controller: _pairing,
                  decoration: InputDecoration(
                    labelText: tr('Only while doing it, I enjoy…'),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('It\'s my workout')),
                  subtitle: Text(
                    tr(
                      'Completed automatically when you finish a workout in Fitness, and the System can adjust your exercises.',
                    ),
                  ),
                  value: _workout,
                  onChanged: (v) => setState(() => _workout = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _valid ? _save : null,
            child: Text(_old == null ? tr('Create quest') : tr('Save')),
          ),
        ],
      ),
    );
  }

  Future<IfThen?> _askIfThen(BuildContext context) async {
    final when = TextEditingController();
    final then = TextEditingController();
    final examples = [
      (
        tr('there\'s no electricity'),
        tr('I do the tiny version by phone light'),
      ),
      (tr('I\'m too tired'), tr('I do only the tiny version')),
      (tr('I\'m away from home'), tr('I do the travel version')),
      (tr('I feel I can\'t do it'), tr('I do the easiest step and stop')),
    ];
    return showDialog<IfThen>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text(tr('If–then plan')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: when,
                  decoration: InputDecoration(labelText: tr('If…')),
                ),
                TextField(
                  controller: then,
                  decoration: InputDecoration(labelText: tr('then I will…')),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (w, t) in examples)
                      ActionChip(
                        label: Text(w),
                        onPressed: () => set(() {
                          when.text = w;
                          then.text = t;
                        }),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d),
              child: Text(tr('Cancel')),
            ),
            FilledButton(
              onPressed: () {
                if (when.text.trim().isEmpty || then.text.trim().isEmpty) {
                  return;
                }
                Navigator.pop(d, IfThen(when.text.trim(), then.text.trim()));
              },
              child: Text(tr('Add')),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.n,
    required this.title,
    required this.why,
    required this.child,
  });

  final int n;
  final String title;
  final String why;
  final Widget child;

  @override
  Widget build(BuildContext context) => SystemPanel(
    title: '$n · ${title.toUpperCase()}',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          why,
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 13,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    ),
  );
}
