import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A single occurrence of an event from the device calendar.
class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.title,
    required this.date,
    required this.start,
    required this.allDay,
    required this.calendarName,
    required this.color,
  });

  final String id;
  final String title;

  /// Local calendar day the event falls on (midnight).
  final DateTime date;

  /// Local start time (same as [date] for all-day events).
  final DateTime start;
  final bool allDay;
  final String calendarName;
  final int color;

  factory CalendarEvent.fromMap(Map<Object?, Object?> map) {
    final begin = (map['begin'] as num).toInt();
    final allDay = map['allDay'] as bool? ?? false;
    // Android stores all-day events at UTC midnight.
    final raw = DateTime.fromMillisecondsSinceEpoch(begin, isUtc: allDay);
    final start = allDay ? DateTime(raw.year, raw.month, raw.day) : raw;
    return CalendarEvent(
      id: map['id'] as String,
      title: map['title'] as String? ?? '',
      date: DateTime(start.year, start.month, start.day),
      start: start,
      allDay: allDay,
      calendarName: map['calendar'] as String? ?? '',
      color: (map['color'] as num?)?.toInt() ?? 0xFF1A9CD8,
    );
  }
}

class CalendarPermissionDenied implements Exception {
  const CalendarPermissionDenied();
}

/// Read-only access to the device calendar (Android, via
/// `android/.../calendar/CalendarChannel.kt`).
class DeviceCalendarService {
  static const _channel = MethodChannel('com.mdtaha.mykit/calendar');

  Future<bool> hasPermission() async =>
      await _channel.invokeMethod<bool>('hasPermission') ?? false;

  Future<bool> requestPermission() async =>
      await _channel.invokeMethod<bool>('requestPermission') ?? false;

  Future<void> openAppSettings() => _channel.invokeMethod('openSettings');

  /// Events between [from] and [to], sorted by start. Asks for permission
  /// first; throws [CalendarPermissionDenied] if refused.
  Future<List<CalendarEvent>> events({
    required DateTime from,
    required DateTime to,
  }) async {
    if (!await requestPermission()) throw const CalendarPermissionDenied();
    final raw = await _channel.invokeListMethod<Map<Object?, Object?>>(
      'getEvents',
      {'start': from.millisecondsSinceEpoch, 'end': to.millisecondsSinceEpoch},
    );
    return (raw ?? []).map(CalendarEvent.fromMap).toList();
  }
}

final deviceCalendarServiceProvider = Provider<DeviceCalendarService>(
  (ref) => DeviceCalendarService(),
);
