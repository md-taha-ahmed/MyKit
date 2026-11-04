import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/i18n/i18n.dart';
import '../../domain/services/countdown_calculator.dart';
import '../screens/calendar_event_picker_screen.dart';

/// Result of the "Select a date" flow.
class DateSelection {
  const DateSelection(this.date, {this.suggestedTitle});

  final DateTime date;

  /// Set when the date came from a calendar event.
  final String? suggestedTitle;
}

enum _DateSource { specific, daysFromToday, calendarEvent }

/// Asks how to pick the date, then runs the matching picker.
Future<DateSelection?> selectCountdownDate(
  BuildContext context, {
  required DateTime current,
}) async {
  final source = await showDialog<_DateSource>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(tr('Select a date')),
      children: [
        _SourceOption(
          icon: Icons.event,
          label: tr('Specific date'),
          value: _DateSource.specific,
        ),
        _SourceOption(
          icon: Icons.more_time,
          label: tr('Number of days from today'),
          value: _DateSource.daysFromToday,
        ),
        _SourceOption(
          icon: Icons.calendar_month,
          label: tr('Event from your calendar'),
          value: _DateSource.calendarEvent,
        ),
      ],
    ),
  );
  if (source == null || !context.mounted) return null;

  switch (source) {
    case _DateSource.specific:
      final now = DateTime.now();
      final picked = await showDatePicker(
        context: context,
        initialDate: current,
        firstDate: DateTime(now.year - 10),
        lastDate: DateTime(now.year + 100),
      );
      return picked == null ? null : DateSelection(picked);

    case _DateSource.daysFromToday:
      final picked = await showDialog<DateTime>(
        context: context,
        builder: (_) => _DaysFromTodayDialog(current: current),
      );
      return picked == null ? null : DateSelection(picked);

    case _DateSource.calendarEvent:
      final event = await CalendarEventPickerScreen.open(context);
      return event == null
          ? null
          : DateSelection(event.date, suggestedTitle: event.title);
  }
}

class _SourceOption extends StatelessWidget {
  const _SourceOption({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final _DateSource value;

  @override
  Widget build(BuildContext context) {
    return SimpleDialogOption(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      onPressed: () => Navigator.pop(context, value),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70),
          const SizedBox(width: 16),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 17))),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Number of days from today
// ---------------------------------------------------------------------------

enum _Span {
  days('Days'),
  weeks('Weeks'),
  months('Months');

  const _Span(this._label);
  final String _label;
  String get label => tr(_label);
}

class _DaysFromTodayDialog extends StatefulWidget {
  const _DaysFromTodayDialog({required this.current});

  final DateTime current;

  @override
  State<_DaysFromTodayDialog> createState() => _DaysFromTodayDialogState();
}

class _DaysFromTodayDialogState extends State<_DaysFromTodayDialog> {
  static const _presets = <(int, _Span, String)>[
    (7, _Span.days, '1 week'),
    (30, _Span.days, '30 days'),
    (100, _Span.days, '100 days'),
    (6, _Span.months, '6 months'),
    (12, _Span.months, '1 year'),
  ];
  static const _max = 36500;

  late final TextEditingController _amount;
  _Span _span = _Span.days;
  final _today = CountdownCalculator.dateOnly(DateTime.now());

  @override
  void initState() {
    super.initState();
    final days = CountdownCalculator.daysBetween(_today, widget.current);
    _amount = TextEditingController(text: days > 0 ? '$days' : '30');
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  int? get _value {
    final n = int.tryParse(_amount.text.trim());
    if (n == null || n < 0 || n > _max) return null;
    return n;
  }

  DateTime? get _result {
    final n = _value;
    if (n == null) return null;
    return switch (_span) {
      _Span.days => DateTime(_today.year, _today.month, _today.day + n),
      _Span.weeks => DateTime(_today.year, _today.month, _today.day + n * 7),
      _Span.months => CountdownCalculator.addMonths(_today, n),
    };
  }

  void _applyPreset(int amount, _Span span) {
    setState(() {
      _span = span;
      _amount.text = '$amount';
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final days = result == null
        ? null
        : CountdownCalculator.daysBetween(_today, result);

    return AlertDialog(
      title: Text(tr('Days from today')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                errorText: result == null
                    ? tr('Enter 0 – {_max}', {'_max': _max})
                    : null,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (result != null) Navigator.pop(context, result);
              },
            ),
            const SizedBox(height: 12),
            SegmentedButton<_Span>(
              showSelectedIcon: false,
              segments: [
                for (final s in _Span.values)
                  ButtonSegment(value: s, label: Text(s.label)),
              ],
              selected: {_span},
              onSelectionChanged: (s) => setState(() => _span = s.first),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final (amount, span, label) in _presets)
                  ActionChip(
                    label: Text(tr(label)),
                    onPressed: () => _applyPreset(amount, span),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (result != null)
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: DateFormat('EEEE, d MMMM y').format(result),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    if (_span != _Span.days)
                      TextSpan(
                        text: tr('\n{days} days from today', {'days': days}),
                        style: const TextStyle(color: Colors.white60),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Cancel')),
        ),
        FilledButton(
          onPressed: result == null
              ? null
              : () => Navigator.pop(context, result),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
