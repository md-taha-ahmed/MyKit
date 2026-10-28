import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/calendar/device_calendar_service.dart';
import '../../domain/services/countdown_calculator.dart';
import '../providers/countdown_providers.dart';

/// Full-screen picker listing upcoming device-calendar events.
class CalendarEventPickerScreen extends ConsumerStatefulWidget {
  const CalendarEventPickerScreen({super.key});

  static Future<CalendarEvent?> open(BuildContext context) {
    return Navigator.of(context).push<CalendarEvent>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const CalendarEventPickerScreen(),
      ),
    );
  }

  @override
  ConsumerState<CalendarEventPickerScreen> createState() =>
      _CalendarEventPickerScreenState();
}

class _CalendarEventPickerScreenState
    extends ConsumerState<CalendarEventPickerScreen>
    with WidgetsBindingObserver {
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Reload after returning from system settings (permission may be granted).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ref.read(upcomingCalendarEventsProvider).error
            is CalendarPermissionDenied) {
      ref.invalidate(upcomingCalendarEventsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(upcomingCalendarEventsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick an event'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search events',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
        ),
      ),
      body: events.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => error is CalendarPermissionDenied
            ? _Message(
                icon: Icons.lock_outline,
                text:
                    'MyKit needs permission to read your calendar to list '
                    'your events. Nothing is changed or uploaded.',
                actions: [
                  FilledButton(
                    onPressed: () =>
                        ref.invalidate(upcomingCalendarEventsProvider),
                    child: const Text('Allow access'),
                  ),
                  TextButton(
                    onPressed: () => ref
                        .read(deviceCalendarServiceProvider)
                        .openAppSettings(),
                    child: const Text('Open settings'),
                  ),
                ],
              )
            : _Message(
                icon: Icons.error_outline,
                text: 'Could not read your calendar.\n$error',
                actions: [
                  FilledButton(
                    onPressed: () =>
                        ref.invalidate(upcomingCalendarEventsProvider),
                    child: const Text('Try again'),
                  ),
                ],
              ),
        data: (all) {
          final filtered = _query.isEmpty
              ? all
              : all
                    .where(
                      (e) =>
                          e.title.toLowerCase().contains(_query) ||
                          e.calendarName.toLowerCase().contains(_query),
                    )
                    .toList();
          if (filtered.isEmpty) {
            return _Message(
              icon: Icons.event_busy,
              text: all.isEmpty
                  ? 'No upcoming events in the next two years.'
                  : 'No events match "$_query".',
            );
          }
          return _EventList(events: filtered);
        },
      ),
    );
  }
}

/// Events grouped under month headers.
class _EventList extends StatelessWidget {
  const _EventList({required this.events});

  final List<CalendarEvent> events;

  @override
  Widget build(BuildContext context) {
    final monthFormat = DateFormat('MMMM y');
    final items = <Object>[];
    String? lastMonth;
    for (final e in events) {
      final month = monthFormat.format(e.date);
      if (month != lastMonth) {
        items.add(month);
        lastMonth = month;
      }
      items.add(e);
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        if (item is String) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
            child: Text(
              item,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }
        return _EventTile(event: item as CalendarEvent);
      },
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});

  final CalendarEvent event;

  @override
  Widget build(BuildContext context) {
    final days = CountdownCalculator.daysBetween(DateTime.now(), event.date);
    final when = event.allDay ? 'All day' : DateFormat.jm().format(event.start);
    final away = switch (days) {
      0 => 'Today',
      1 => 'Tomorrow',
      _ => 'in $days days',
    };

    return ListTile(
      onTap: () => Navigator.pop(context, event),
      leading: SizedBox(
        width: 44,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              DateFormat('EEE').format(event.date),
              style: const TextStyle(fontSize: 12, color: Colors.white60),
            ),
            Text(
              '${event.date.day}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      title: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Color(event.color),
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              event.title.isEmpty ? '(No title)' : event.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      subtitle: Text(
        [
          when,
          if (event.calendarName.isNotEmpty) event.calendarName,
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(away, style: const TextStyle(color: Colors.white60)),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    this.actions = const [],
  });

  final IconData icon;
  final String text;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Colors.white30),
            const SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            ...actions,
          ],
        ),
      ),
    );
  }
}
