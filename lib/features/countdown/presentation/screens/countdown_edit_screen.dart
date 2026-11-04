import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/i18n/i18n.dart';
import '../../countdown_routes.dart';
import '../../domain/entities/countdown.dart';
import '../../domain/entities/countdown_enums.dart';
import '../providers/countdown_providers.dart';
import '../widgets/color_picker_sheet.dart';
import '../widgets/countdown_ring.dart';
import '../widgets/date_selection.dart';
import '../widgets/theme_picker_sheet.dart';

final _dateFormat = DateFormat('dd/MM/yy');

class CountdownEditScreen extends ConsumerStatefulWidget {
  const CountdownEditScreen({super.key, this.countdownId});

  /// null = create a new countdown.
  final String? countdownId;

  @override
  ConsumerState<CountdownEditScreen> createState() =>
      _CountdownEditScreenState();
}

class _CountdownEditScreenState extends ConsumerState<CountdownEditScreen> {
  late final TextEditingController _title;
  late final TextEditingController _notes;
  bool _lightPreview = false;

  CountdownEditorNotifier get _editor =>
      ref.read(countdownEditorProvider(widget.countdownId).notifier);

  @override
  void initState() {
    super.initState();
    final draft = ref.read(countdownEditorProvider(widget.countdownId));
    _title = TextEditingController(text: draft.title);
    _notes = TextEditingController(text: draft.notes);
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _update(Countdown Function(Countdown d) change) =>
      _editor.update(change);

  Future<void> _save() async {
    await _editor.save();
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(CountdownRoutes.list);
    }
  }

  Future<void> _pickDate(Countdown draft) async {
    final selection = await selectCountdownDate(
      context,
      current: draft.targetDate,
    );
    if (selection == null) return;
    _editor.setTargetDate(selection.date);

    // Calendar events also fill in an empty title.
    final title = selection.suggestedTitle?.trim() ?? '';
    if (title.isNotEmpty && _title.text.trim().isEmpty) {
      _title.text = title;
      _update((d) => d.copyWith(title: title));
    }
  }

  Future<void> _pickColor(
    String title,
    int current,
    Countdown Function(Countdown d, int color) apply,
  ) async {
    final color = await showColorPickerSheet(
      context,
      title: title,
      selected: current,
    );
    if (color != null) _update((d) => apply(d, color));
  }

  Future<void> _pickTheme(Countdown draft) async {
    final theme = await showThemePickerSheet(context, countdown: draft);
    if (theme == null) return;
    _update(
      (d) => d.copyWith(
        ringColor: theme.ringColor,
        backgroundColor: theme.backgroundColor,
        trackColor: theme.trackColor,
        textColor: theme.textColor,
      ),
    );
  }

  Future<void> _onMenu(_MenuAction action) async {
    switch (action) {
      case _MenuAction.addToHome:
        final widgetService = ref.read(countdownHomeWidgetServiceProvider);
        if (!await widgetService.canPinWidget()) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                tr(
                  'Your launcher can\'t add widgets from apps. Long-press the home screen → Widgets → MyKit instead.',
                ),
              ),
            ),
          );
          return;
        }
        // The widget reads saved data, so persist first.
        await _editor.save();
        final draft = ref.read(countdownEditorProvider(widget.countdownId));
        await widgetService.pinWidget(draft.id);
      case _MenuAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(tr('Delete countdown?')),
            content: Text(
              tr(
                'Home screen widgets showing it will ask you to pick another one.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr('Cancel')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(tr('Delete')),
              ),
            ],
          ),
        );
        if (confirmed != true || widget.countdownId == null) return;
        await ref.read(countdownsProvider.notifier).delete(widget.countdownId!);
        if (mounted) context.go(CountdownRoutes.list);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(countdownEditorProvider(widget.countdownId));
    final isNew = widget.countdownId == null;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go(CountdownRoutes.list),
        ),
        title: Text(isNew ? tr('New countdown') : tr('Edit countdown')),
        actions: [
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24),
            ),
            child: const Text(
              'SAVE',
              style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: .5),
            ),
          ),
          PopupMenuButton<_MenuAction>(
            onSelected: _onMenu,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _MenuAction.addToHome,
                child: Text(tr('Add to home screen')),
              ),
              if (!isNew)
                PopupMenuItem(
                  value: _MenuAction.delete,
                  child: Text(tr('Delete')),
                ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 8, 16, 48),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: _PreviewCard(
              countdown: draft,
              light: _lightPreview,
              onToggleLight: (v) => setState(() => _lightPreview = v),
            ),
          ),
          const SizedBox(height: 28),

          // Date & time
          _Section(
            icon: Icons.calendar_month,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _FieldButton(
                        label: tr('Select a date'),
                        value: _dateFormat.format(draft.targetDate),
                        onTap: () => _pickDate(draft),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: _FieldButton(
                        label: tr('Select a time'),
                        value: tr('All day'),
                      ),
                    ),
                  ],
                ),
                _Hint(tr('Cannot set time for widgets.')),
              ],
            ),
          ),

          // Recurrence
          _Section(
            icon: Icons.refresh,
            child: _Dropdown<Recurrence>(
              label: tr('Recurrence'),
              value: draft.recurrence,
              items: {for (final r in Recurrence.values) r: r.label},
              onChanged: (v) => _update((d) => d.copyWith(recurrence: v)),
            ),
          ),

          // Title
          _Section(
            icon: Icons.label,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: tr('What is on that day?'),
                  ),
                  onChanged: (v) => _update((d) => d.copyWith(title: v)),
                ),
                _SwitchRow(
                  label: tr('Show title in widget'),
                  value: draft.showTitleInWidget,
                  onChanged: (v) =>
                      _update((d) => d.copyWith(showTitleInWidget: v)),
                ),
              ],
            ),
          ),

          // Notes
          _Section(
            icon: Icons.notes,
            child: TextField(
              controller: _notes,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(hintText: tr('Your notes')),
              onChanged: (v) => _update((d) => d.copyWith(notes: v)),
            ),
          ),

          // Colors
          _Section(
            icon: Icons.palette,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _ColorChoice(
                      tooltip: tr('Ring color'),
                      color: draft.ringColor,
                      onTap: () => _pickColor(
                        tr('Ring color'),
                        draft.ringColor,
                        (d, c) => d.copyWith(ringColor: c),
                      ),
                    ),
                    _ColorChoice(
                      tooltip: tr('Background color'),
                      color: draft.backgroundColor,
                      onTap: () => _pickColor(
                        tr('Background color'),
                        draft.backgroundColor,
                        (d, c) => d.copyWith(backgroundColor: c),
                      ),
                    ),
                    _ColorChoice(
                      tooltip: tr('Ring track color'),
                      color: draft.trackColor,
                      onTap: () => _pickColor(
                        tr('Ring track color'),
                        draft.trackColor,
                        (d, c) => d.copyWith(trackColor: c),
                      ),
                    ),
                    _ColorChoice(
                      tooltip: tr('Text color'),
                      color: draft.textColor,
                      onTap: () => _pickColor(
                        tr('Text color'),
                        draft.textColor,
                        (d, c) => d.copyWith(textColor: c),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () => _pickTheme(draft),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF48484C),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                  ),
                  child: Text(
                    tr('SELECT THEME'),
                    style: TextStyle(letterSpacing: 1.2),
                  ),
                ),
              ],
            ),
          ),

          // Unit
          _Section(
            icon: Icons.tune,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Dropdown<CountUnit>(
                  label: tr('Count for'),
                  value: draft.unit,
                  items: {for (final u in CountUnit.values) u: u.label},
                  onChanged: (v) => _update((d) => d.copyWith(unit: v)),
                ),
                _SwitchRow(
                  label: tr('Show label'),
                  value: draft.showLabel,
                  onChanged: (v) => _update((d) => d.copyWith(showLabel: v)),
                ),
              ],
            ),
          ),

          // Decrease circle
          _Section(
            icon: Icons.timelapse,
            alignIconToTop: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SwitchRow(
                  label: tr('Decrease circle with time'),
                  large: true,
                  value: draft.decreaseCircle,
                  onChanged: (v) =>
                      _update((d) => d.copyWith(decreaseCircle: v)),
                ),
                const SizedBox(height: 4),
                _Dropdown<int>(
                  label: tr('When should the circle start decreasing?'),
                  value: draft.decreaseStartDays,
                  enabled: draft.decreaseCircle,
                  items: {
                    for (final days in _startDayOptions(
                      draft.decreaseStartDays,
                    ))
                      days: days == 1
                          ? tr('1 day before deadline')
                          : tr('{days} days before deadline', {'days': days}),
                  },
                  onChanged: _editor.setDecreaseStartDays,
                ),
              ],
            ),
          ),

          // Font
          _Section(
            icon: Icons.text_fields,
            child: _Dropdown<CountdownFont>(
              label: tr('Select font'),
              value: draft.font,
              items: {for (final f in CountdownFont.values) f: f.label},
              itemStyle: (f) => TextStyle(fontFamily: f.family),
              onChanged: (v) => _update((d) => d.copyWith(font: v)),
            ),
          ),

          _Section(
            icon: Icons.blur_on,
            alignIconToTop: false,
            child: _SwitchRow(
              label: tr('Drop shadow'),
              large: true,
              value: draft.dropShadow,
              onChanged: (v) => _update((d) => d.copyWith(dropShadow: v)),
            ),
          ),
          _Section(
            icon: Icons.rotate_right,
            alignIconToTop: false,
            child: _SwitchRow(
              label: tr('Clockwise'),
              large: true,
              value: draft.clockwise,
              onChanged: (v) => _update((d) => d.copyWith(clockwise: v)),
            ),
          ),
        ],
      ),
    );
  }

  static List<int> _startDayOptions(int current) {
    final options = {7, 14, 30, 60, 90, 180, 365, current}.toList()..sort();
    return options;
  }
}

enum _MenuAction { addToHome, delete }

// ---------------------------------------------------------------------------
// Building blocks
// ---------------------------------------------------------------------------

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.countdown,
    required this.light,
    required this.onToggleLight,
  });

  final Countdown countdown;
  final bool light;
  final ValueChanged<bool> onToggleLight;

  @override
  Widget build(BuildContext context) {
    final showTitle =
        countdown.showTitleInWidget && countdown.title.trim().isNotEmpty;
    final fg = light ? Colors.black87 : Colors.white70;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: light ? const Color(0xFFE9E9EC) : const Color(0xFF333336),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 16),
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Tooltip(
              message: tr('Light wallpaper preview'),
              child: Switch(value: light, onChanged: onToggleLight),
            ),
          ),
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                tr('Preview'),
                style: TextStyle(color: fg, fontSize: 16),
              ),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                children: [
                  CountdownRing(countdown: countdown, size: 136),
                  if (showTitle)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        countdown.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: light ? Colors.black : Colors.white,
                          fontSize: 15,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.child,
    this.alignIconToTop = true,
  });

  final IconData icon;
  final Widget child;
  final bool alignIconToTop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: alignIconToTop
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 60,
            child: Padding(
              padding: EdgeInsets.only(top: alignIconToTop ? 18 : 0),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _FieldButton extends StatelessWidget {
  const _FieldButton({required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        isEmpty: false,
        decoration: InputDecoration(
          labelText: label,
          enabled: enabled,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          suffixIcon: Icon(
            Icons.arrow_drop_down,
            color: enabled ? Colors.white : Colors.white38,
          ),
        ),
        child: Text(
          value,
          style: TextStyle(
            fontSize: 17,
            color: enabled ? Colors.white : Colors.white38,
          ),
        ),
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.enabled = true,
    this.itemStyle,
  });

  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;
  final bool enabled;
  final TextStyle Function(T value)? itemStyle;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      // Rebuild when the value is changed from outside the dropdown.
      key: ValueKey(value),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
      ),
      style: const TextStyle(fontSize: 17, color: Colors.white),
      iconEnabledColor: Colors.white,
      items: [
        for (final entry in items.entries)
          DropdownMenuItem(
            value: entry.key,
            child: Text(
              entry.value,
              overflow: TextOverflow.ellipsis,
              style: itemStyle?.call(entry.key),
            ),
          ),
      ],
      onChanged: enabled
          ? (v) {
              if (v != null) onChanged(v);
            }
          : null,
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.large = false,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: large ? 0 : 8),
      child: Row(
        children: [
          Flexible(
            child: Text(label, style: TextStyle(fontSize: large ? 18 : 15)),
          ),
          const SizedBox(width: 8),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _ColorChoice extends StatelessWidget {
  const _ColorChoice({
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  final String tooltip;
  final int color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Tooltip(
        message: tooltip,
        child: ColorDot(color: color, size: 56, onTap: onTap),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, left: 16),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white70, fontSize: 15),
      ),
    );
  }
}
