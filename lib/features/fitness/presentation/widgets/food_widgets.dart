import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/i18n/i18n.dart';
import '../../domain/food.dart';
import '../providers/food_providers.dart';

class MealPicker extends StatelessWidget {
  const MealPicker({super.key, required this.value, required this.onChanged});

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

/// Chips that wrap onto new lines, showing the first [limit] with a "More"
/// chip for the rest, so a long list doesn't take over the screen.
class FoldingChips extends StatefulWidget {
  const FoldingChips({super.key, required this.chips, this.limit = 6});

  final List<Widget> chips;
  final int limit;

  @override
  State<FoldingChips> createState() => _FoldingChipsState();
}

class _FoldingChipsState extends State<FoldingChips> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final all = widget.chips;
    final hidden = all.length - widget.limit;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        ...(_open || hidden <= 0 ? all : all.take(widget.limit)),
        if (hidden > 0)
          ActionChip(
            avatar: Icon(_open ? Icons.expand_less : Icons.expand_more),
            label: Text(_open ? tr('Less') : tr('More ({n})', {'n': hidden})),
            onPressed: () => setState(() => _open = !_open),
          ),
      ],
    );
  }
}

/// Edit a logged food: name, calories, meal — or delete it.
Future<void> editFoodEntry(
  BuildContext context,
  WidgetRef ref,
  FoodEntry entry,
) async {
  final name = TextEditingController(text: entry.name);
  final kcal = TextEditingController(text: '${entry.kcal}');
  var meal = entry.meal;
  final action = await showDialog<String>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, set) => AlertDialog(
        title: Text(tr('Edit food')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: InputDecoration(labelText: tr('Food')),
            ),
            TextField(
              controller: kcal,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              decoration: InputDecoration(labelText: tr('Calories (kcal)')),
            ),
            const SizedBox(height: 10),
            MealPicker(value: meal, onChanged: (m) => set(() => meal = m)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, 'delete'),
            child: Text(tr('Delete')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, 'save'),
            child: Text(tr('Save')),
          ),
        ],
      ),
    ),
  );
  final log = ref.read(foodLogProvider.notifier);
  if (action == 'delete') return log.remove(entry.id);
  final value = int.tryParse(kcal.text.trim());
  if (action != 'save' || name.text.trim().isEmpty || value == null) return;
  await log.update(
    entry.copyWith(name: name.text.trim(), kcal: value, meal: meal),
  );
}

/// Create or edit a saved meal: a name and its foods. [items] prefills a new
/// one (e.g. from what you ate for breakfast today).
Future<void> editSavedMeal(
  BuildContext context,
  WidgetRef ref, {
  SavedMeal? meal,
  List<FoodItem>? items,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _SavedMealEditor(meal: meal, items: items),
);

class _Row {
  _Row(FoodItem? i)
    : name = TextEditingController(text: i?.name),
      kcal = TextEditingController(text: i == null ? '' : '${i.kcal}');

  final TextEditingController name;
  final TextEditingController kcal;

  FoodItem? get item {
    final k = int.tryParse(kcal.text.trim());
    final n = name.text.trim();
    return n.isEmpty || k == null ? null : (name: n, kcal: k);
  }

  void dispose() {
    name.dispose();
    kcal.dispose();
  }
}

class _SavedMealEditor extends ConsumerStatefulWidget {
  const _SavedMealEditor({this.meal, this.items});

  final SavedMeal? meal;
  final List<FoodItem>? items;

  @override
  ConsumerState<_SavedMealEditor> createState() => _SavedMealEditorState();
}

class _SavedMealEditorState extends ConsumerState<_SavedMealEditor> {
  late final _name = TextEditingController(text: widget.meal?.name);
  late final _rows = [
    for (final i in widget.meal?.items ?? widget.items ?? const <FoodItem>[])
      _Row(i),
  ];

  @override
  void initState() {
    super.initState();
    if (_rows.isEmpty) _rows.add(_Row(null));
  }

  @override
  void dispose() {
    _name.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  int get _total => _rows.fold(0, (s, r) => s + (r.item?.kcal ?? 0));

  Future<void> _save() async {
    final items = [for (final r in _rows) ?r.item];
    final name = _name.text.trim();
    if (name.isEmpty || items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Give it a name and at least one food.'))),
      );
      return;
    }
    await ref
        .read(savedMealsProvider.notifier)
        .save(
          SavedMeal(
            id: widget.meal?.id ?? const Uuid().v4(),
            name: name,
            items: items,
          ),
        );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final recent = ref.read(foodLogProvider.notifier).recent;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              widget.meal == null ? tr('New meal') : tr('Edit meal'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            TextField(
              controller: _name,
              autofocus: widget.meal == null,
              decoration: InputDecoration(
                labelText: tr('Name'),
                hintText: tr('e.g. My usual breakfast'),
              ),
            ),
            const SizedBox(height: 12),
            for (final (i, r) in _rows.indexed)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: r.name,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(labelText: tr('Food')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 104,
                    child: TextField(
                      controller: r.kcal,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.end,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: const InputDecoration(
                        suffixText: ' kcal',
                        suffixStyle: TextStyle(
                          fontSize: 13,
                          color: Colors.white60,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: tr('Remove'),
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => setState(() {
                      _rows.removeAt(i).dispose();
                      if (_rows.isEmpty) _rows.add(_Row(null));
                    }),
                  ),
                ],
              ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => setState(() => _rows.add(_Row(null))),
                icon: const Icon(Icons.add),
                label: Text(tr('Add a food')),
              ),
            ),
            if (recent.isNotEmpty) ...[
              Text(
                tr('Or tap one you ate before:'),
                style: const TextStyle(color: Colors.white60, fontSize: 12.5),
              ),
              const SizedBox(height: 6),
              FoldingChips(
                chips: [
                  for (final f in recent)
                    ActionChip(
                      label: Text('${f.name} · ${f.kcal}'),
                      onPressed: () => setState(() {
                        // Fill an empty row first.
                        final empty = _rows.where(
                          (r) => r.name.text.trim().isEmpty,
                        );
                        if (empty.isEmpty) {
                          _rows.add(_Row(f));
                        } else {
                          empty.first.name.text = f.name;
                          empty.first.kcal.text = '${f.kcal}';
                        }
                      }),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Text(
              tr('Total: {n} kcal', {'n': _total}),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (widget.meal != null)
                  TextButton(
                    onPressed: () async {
                      await ref
                          .read(savedMealsProvider.notifier)
                          .remove(widget.meal!.id);
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: Text(tr('Delete')),
                  ),
                const Spacer(),
                FilledButton(onPressed: _save, child: Text(tr('Save'))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
