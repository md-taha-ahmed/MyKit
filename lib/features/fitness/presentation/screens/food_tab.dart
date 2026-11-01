import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/ai/gemini_client.dart';
import '../../../../core/ai/gemini_key_screen.dart';
import '../../../../core/i18n/i18n.dart';
import '../../data/food_estimator.dart';
import '../../domain/food.dart';
import '../providers/fitness_providers.dart';
import '../providers/food_providers.dart';

/// Calories today against a target worked out from your weight and height;
/// add food by hand, by describing it, or with a photo.
class FoodTab extends ConsumerWidget {
  const FoodTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = foodDay(now);
    final entries = ref
        .watch(foodLogProvider)
        .where((e) => e.day == today)
        .toList();
    final eaten = entries.fold<int>(0, (s, e) => s + e.kcal);
    final target = ref.watch(calorieTargetProvider);
    final byDay = ref.watch(caloriesByDayProvider);
    final left = target.target - eaten;
    final over = left < 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$eaten',
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        tr('of {target} kcal', {'target': target.target}),
                        style: const TextStyle(color: Colors.white60),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: tr('Daily target'),
                      onPressed: () => _targetSheet(context, ref),
                      icon: const Icon(Icons.tune),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    value: (eaten / target.target).clamp(0, 1).toDouble(),
                    minHeight: 9,
                    color: over ? Colors.orangeAccent : fitnessAccent,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  over
                      ? tr('{n} kcal over today', {'n': -left})
                      : tr('{n} kcal left today', {'n': left}),
                  style: TextStyle(
                    color: over ? Colors.orangeAccent : Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _AddTile(
              icon: Icons.photo_camera_outlined,
              label: tr('Photo'),
              filled: true,
              onTap: () => _photo(context, ref),
            ),
            const SizedBox(width: 8),
            _AddTile(
              icon: Icons.auto_awesome_outlined,
              label: tr('Describe'),
              onTap: () => _describe(context, ref),
            ),
            const SizedBox(width: 8),
            _AddTile(
              icon: Icons.edit_outlined,
              label: tr('Manual'),
              onTap: () => _manual(context, ref),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          tr(
            'Photo and Describe ask Gemini for an estimate — check the numbers before saving.',
          ),
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54),
        ),
        if (ref.read(foodLogProvider.notifier).recent case final recent
            when recent.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(tr('Again'), style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in recent)
                ActionChip(
                  label: Text('${r.name} · ${r.kcal}'),
                  onPressed: () =>
                      ref.read(foodLogProvider.notifier).add(r.name, r.kcal),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        for (final meal in Meal.values)
          if (entries.where((e) => e.meal == meal).toList() case final list
              when list.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 2),
              child: Text(
                '${tr(meal.label)} · ${list.fold<int>(0, (s, e) => s + e.kcal)} kcal',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: fitnessAccent,
                ),
              ),
            ),
            for (final e in list)
              Dismissible(
                key: ValueKey(e.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: AlignmentDirectional.centerEnd,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  color: Colors.red.withValues(alpha: 0.3),
                  child: const Icon(Icons.delete_outline),
                ),
                onDismissed: (_) =>
                    ref.read(foodLogProvider.notifier).remove(e.id),
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(switch (e.source) {
                    FoodSource.photo => Icons.photo_camera_outlined,
                    FoodSource.text => Icons.auto_awesome_outlined,
                    FoodSource.manual => Icons.restaurant,
                  }, size: 20),
                  title: Text(e.name),
                  trailing: Text('${e.kcal} kcal'),
                ),
              ),
          ],
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              tr('Nothing logged today.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54),
            ),
          ),
        const SizedBox(height: 16),
        Text(tr('Last 7 days'), style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        _Week(byDay: byDay, target: target.target),
      ],
    );
  }

  // ---------------------------------------------------------------------------

  Future<void> _manual(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final kcal = TextEditingController();
    var meal = Meal.forTime(DateTime.now());
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text(tr('Add food')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: InputDecoration(labelText: tr('Food')),
              ),
              TextField(
                controller: kcal,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: tr('Calories (kcal)')),
              ),
              const SizedBox(height: 10),
              _MealPicker(value: meal, onChanged: (m) => set(() => meal = m)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: Text(tr('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: Text(tr('Add')),
            ),
          ],
        ),
      ),
    );
    final value = int.tryParse(kcal.text.trim());
    if (ok == true && name.text.trim().isNotEmpty && value != null) {
      await ref
          .read(foodLogProvider.notifier)
          .add(name.text, value, meal: meal);
    }
  }

  Future<void> _describe(BuildContext context, WidgetRef ref) async {
    if (!await _aiReady(context, ref)) return;
    if (!context.mounted) return;
    final text = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('What did you eat?')),
        content: TextField(
          controller: text,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: tr('e.g. a plate of saltah with two breads and tea'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text(tr('Estimate')),
          ),
        ],
      ),
    );
    if (ok != true || text.text.trim().isEmpty || !context.mounted) return;
    await _estimateAndReview(
      context,
      ref,
      ref
          .read(foodEstimatorProvider)
          .estimate(text: text.text, arabic: I18n.isArabic),
      FoodSource.text,
    );
  }

  Future<void> _photo(BuildContext context, WidgetRef ref) async {
    if (!await _aiReady(context, ref)) return;
    if (!context.mounted) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (s) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(tr('Take a photo')),
              onTap: () => Navigator.pop(s, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(tr('Choose from gallery')),
              onTap: () => Navigator.pop(s, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    // Small and compressed: light on mobile data.
    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 70,
    );
    if (file == null || !context.mounted) return;
    final bytes = await file.readAsBytes();
    if (!context.mounted) return;
    final note = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('Anything to add?')),
        content: TextField(
          controller: note,
          minLines: 1,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: tr('Optional: "I ate half", "with 2 breads"…'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text(tr('Estimate')),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
    await _estimateAndReview(
      context,
      ref,
      ref
          .read(foodEstimatorProvider)
          .estimate(
            text: note.text,
            photo: (bytes: bytes, mimeType: 'image/jpeg'),
            arabic: I18n.isArabic,
          ),
      FoodSource.photo,
    );
  }

  Future<bool> _aiReady(BuildContext context, WidgetRef ref) async {
    if (ref.read(geminiClientProvider).isConfigured) return true;
    return openGeminiKeySetup(context);
  }

  /// Shows the estimate to check and adjust, then saves the items.
  Future<void> _estimateAndReview(
    BuildContext context,
    WidgetRef ref,
    Future<FoodEstimate> request,
    FoodSource source,
  ) async {
    final result = await showDialog<_Reviewed>(
      context: context,
      builder: (d) => _EstimateDialog(request: request),
    );
    if (result == null) return;
    final log = ref.read(foodLogProvider.notifier);
    for (final i in result.items) {
      await log.add(
        i.amount.isEmpty ? i.name : '${i.name} (${i.amount})',
        i.kcal,
        meal: result.meal,
        source: source,
      );
    }
  }

  Future<void> _targetSheet(BuildContext context, WidgetRef ref) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => const _TargetSheet(),
      );
}

/// An "add food" button: icon above a short label, so it never squeezes.
class _AddTile extends StatelessWidget {
  const _AddTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.black : fitnessAccent;
    return Expanded(
      child: Material(
        color: filled ? fitnessAccent : fitnessAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: fg),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

typedef _Reviewed = ({List<EstimatedItem> items, Meal meal});

class _EstimateDialog extends StatefulWidget {
  const _EstimateDialog({required this.request});

  final Future<FoodEstimate> request;

  @override
  State<_EstimateDialog> createState() => _EstimateDialogState();
}

class _EstimateDialogState extends State<_EstimateDialog> {
  FoodEstimate? _estimate;
  String? _error;
  final _kcal = <TextEditingController>[];
  final _keep = <bool>[];
  var _meal = Meal.forTime(DateTime.now());

  @override
  void initState() {
    super.initState();
    widget.request.then(
      (e) {
        if (!mounted) return;
        setState(() {
          _estimate = e;
          for (final i in e.items) {
            _kcal.add(TextEditingController(text: '${i.kcal}'));
            _keep.add(true);
          }
        });
      },
      onError: (Object e) {
        if (mounted) {
          setState(() => _error = e is AiException ? e.message : '$e');
        }
      },
    );
  }

  @override
  void dispose() {
    for (final c in _kcal) {
      c.dispose();
    }
    super.dispose();
  }

  int get _total => [
    for (var i = 0; i < _kcal.length; i++)
      if (_keep[i]) int.tryParse(_kcal[i].text) ?? 0,
  ].fold(0, (a, b) => a + b);

  @override
  Widget build(BuildContext context) {
    final e = _estimate;
    return AlertDialog(
      title: Text(tr('Estimate')),
      content: SizedBox(
        width: double.maxFinite,
        child: _error != null
            ? Text(_error!)
            : e == null
            ? const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, item) in e.items.indexed)
                      Row(
                        children: [
                          Checkbox(
                            value: _keep[i],
                            onChanged: (v) =>
                                setState(() => _keep[i] = v ?? false),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.name),
                                if (item.amount.isNotEmpty)
                                  Text(
                                    item.amount,
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 72,
                            child: TextField(
                              controller: _kcal[i],
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.end,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                suffixText: 'kcal',
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 8),
                    Text(
                      tr('Total: {n} kcal', {'n': _total}),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (e.note.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        e.note,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    _MealPicker(
                      value: _meal,
                      onChanged: (m) => setState(() => _meal = m),
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Cancel')),
        ),
        if (e != null)
          FilledButton(
            onPressed: () => Navigator.pop(context, (
              items: [
                for (final (i, item) in e.items.indexed)
                  if (_keep[i])
                    (
                      name: item.name,
                      amount: item.amount,
                      kcal: int.tryParse(_kcal[i].text) ?? item.kcal,
                    ),
              ],
              meal: _meal,
            )),
            child: Text(tr('Save')),
          ),
      ],
    );
  }
}

class _MealPicker extends StatelessWidget {
  const _MealPicker({required this.value, required this.onChanged});

  final Meal value;
  final ValueChanged<Meal> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    children: [
      for (final m in Meal.values)
        ChoiceChip(
          label: Text(tr(m.label)),
          selected: value == m,
          onSelected: (_) => onChanged(m),
        ),
    ],
  );
}

class _Week extends StatelessWidget {
  const _Week({required this.byDay, required this.target});

  final Map<String, int> byDay;
  final int target;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final days = [for (var i = 6; i >= 0; i--) now.subtract(Duration(days: i))];
    final top = [
      target,
      ...days.map((d) => byDay[foodDay(d)] ?? 0),
    ].reduce((a, b) => a > b ? a : b);
    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final d in days)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '${byDay[foodDay(d)] ?? 0}',
                    style: const TextStyle(fontSize: 10, color: Colors.white54),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    height: 80 * ((byDay[foodDay(d)] ?? 0) / top),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: (byDay[foodDay(d)] ?? 0) > target
                          ? Colors.orangeAccent
                          : fitnessAccent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${d.day}',
                    style: const TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Age, sex, activity and goal → a target from your weight and height.
class _TargetSheet extends ConsumerWidget {
  const _TargetSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(calorieSettingsProvider);
    final t = ref.watch(calorieTargetProvider);
    final weight = ref.watch(currentWeightProvider);
    final height = ref.watch(fitnessProfileProvider).heightCm;
    final notifier = ref.read(calorieSettingsProvider.notifier);
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Daily target'), style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              tr(
                'From your weight ({w} kg, your latest log) and height ({h} cm, in your profile).',
                {
                  'w': weight.toStringAsFixed(1),
                  'h': height.toStringAsFixed(0),
                },
              ),
              style: const TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: Text(tr('Age'))),
                IconButton(
                  onPressed: s.age > 14
                      ? () => notifier.update(s.copyWith(age: s.age - 1))
                      : null,
                  icon: const Icon(Icons.remove),
                ),
                Text(
                  '${s.age}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                IconButton(
                  onPressed: s.age < 90
                      ? () => notifier.update(s.copyWith(age: s.age + 1))
                      : null,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: true, label: Text(tr('Male'))),
                ButtonSegment(value: false, label: Text(tr('Female'))),
              ],
              selected: {s.male},
              onSelectionChanged: (v) =>
                  notifier.update(s.copyWith(male: v.first)),
            ),
            const SizedBox(height: 12),
            Text(tr('Activity'), style: theme.textTheme.titleSmall),
            for (final a in Activity.values)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  s.activity == a
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: s.activity == a ? fitnessAccent : null,
                ),
                title: Text(tr(a.label)),
                onTap: () => notifier.update(s.copyWith(activity: a)),
              ),
            Text(tr('Goal'), style: theme.textTheme.titleSmall),
            Wrap(
              spacing: 6,
              children: [
                for (final g in WeightGoal.values)
                  ChoiceChip(
                    label: Text(tr(g.label)),
                    selected: s.goal == g,
                    onSelected: (_) => notifier.update(s.copyWith(goal: g)),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('{n} kcal a day', {'n': t.target}),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      tr(
                        'Resting {bmr} kcal · with activity {m} kcal (keeps your weight).',
                        {'bmr': t.bmr, 'm': t.maintenance},
                      ),
                      style: const TextStyle(color: Colors.white60),
                    ),
                    if (s.goal == WeightGoal.lose && !t.manual)
                      Text(
                        tr('About ½ kg a week. Never below a safe minimum.'),
                        style: const TextStyle(color: Colors.white60),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Use my own number')),
              value: s.manualTarget != null,
              onChanged: (on) => notifier.update(
                on
                    ? s.copyWith(manualTarget: t.target)
                    : s.copyWith(clearManual: true),
              ),
            ),
            if (s.manualTarget != null)
              Slider(
                value: s.manualTarget!.toDouble().clamp(1000, 5000),
                min: 1000,
                max: 5000,
                divisions: 80,
                label: '${s.manualTarget}',
                onChanged: (v) => notifier.update(
                  s.copyWith(manualTarget: (v / 50).round() * 50),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
