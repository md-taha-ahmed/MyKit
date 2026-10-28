import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/calendar/device_calendar_service.dart';
import '../../../../core/storage/shared_preferences_provider.dart';
import '../../data/datasources/countdown_local_data_source.dart';
import '../../data/repositories/countdown_repository_impl.dart';
import '../../data/services/countdown_home_widget_service.dart';
import '../../domain/entities/countdown.dart';
import '../../domain/repositories/countdown_repository.dart';
import '../../domain/services/countdown_calculator.dart';

// ---------------------------------------------------------------------------
// Dependencies
// ---------------------------------------------------------------------------

final countdownHomeWidgetServiceProvider = Provider<CountdownHomeWidgetService>(
  (ref) => CountdownHomeWidgetService(),
);

final countdownRepositoryProvider = Provider<CountdownRepository>((ref) {
  return CountdownRepositoryImpl(
    CountdownLocalDataSource(ref.watch(sharedPreferencesProvider)),
    ref.watch(countdownHomeWidgetServiceProvider),
  );
});

// ---------------------------------------------------------------------------
// Countdown list
// ---------------------------------------------------------------------------

final countdownsProvider =
    NotifierProvider<CountdownsNotifier, List<Countdown>>(
      CountdownsNotifier.new,
    );

class CountdownsNotifier extends Notifier<List<Countdown>> {
  CountdownRepository get _repo => ref.read(countdownRepositoryProvider);

  @override
  List<Countdown> build() {
    final items = _repo.getAll();
    // Push the latest data to home-screen widgets on every app start.
    Future.microtask(() => _repo.saveAll(items));
    return items;
  }

  Future<void> upsert(Countdown countdown) async {
    final exists = state.any((c) => c.id == countdown.id);
    state = exists
        ? [for (final c in state) c.id == countdown.id ? countdown : c]
        : [...state, countdown];
    await _repo.saveAll(state);
  }

  Future<void> delete(String id) async {
    state = state.where((c) => c.id != id).toList();
    await _repo.saveAll(state);
  }
}

final countdownByIdProvider = Provider.family<Countdown?, String>((ref, id) {
  final items = ref.watch(countdownsProvider);
  for (final c in items) {
    if (c.id == id) return c;
  }
  return null;
});

// ---------------------------------------------------------------------------
// Editor (draft state for the edit screen)
// ---------------------------------------------------------------------------

/// Draft of a countdown being edited. Pass `null` to create a new one.
final countdownEditorProvider = NotifierProvider.autoDispose
    .family<CountdownEditorNotifier, Countdown, String?>(
      CountdownEditorNotifier.new,
    );

class CountdownEditorNotifier extends Notifier<Countdown> {
  CountdownEditorNotifier(this.countdownId);

  final String? countdownId;

  /// Whether the user picked a custom "start decreasing" value. If not, it
  /// follows the selected date (like the original app does).
  bool _startDaysTouched = false;

  bool get isNew => countdownId == null;

  @override
  Countdown build() {
    final existing = countdownId == null
        ? null
        : ref.read(countdownByIdProvider(countdownId!));
    if (existing != null) {
      _startDaysTouched = true;
      return existing;
    }

    final now = DateTime.now();
    final target = DateTime(now.year, now.month, now.day + 30);
    return Countdown(
      id: const Uuid().v4(),
      targetDate: target,
      createdAt: now,
      decreaseStartDays: 30,
    );
  }

  void update(Countdown Function(Countdown draft) change) {
    state = change(state);
  }

  void setTargetDate(DateTime date) {
    final target = CountdownCalculator.dateOnly(date);
    var next = state.copyWith(targetDate: target);
    if (!_startDaysTouched) {
      final days = CountdownCalculator.daysBetween(DateTime.now(), target);
      next = next.copyWith(decreaseStartDays: days < 1 ? 1 : days);
    }
    state = next;
  }

  void setDecreaseStartDays(int days) {
    _startDaysTouched = true;
    state = state.copyWith(decreaseStartDays: days);
  }

  Future<void> save() => ref.read(countdownsProvider.notifier).upsert(state);
}

// ---------------------------------------------------------------------------
// Calendar events (for "Event from your calendar")
// ---------------------------------------------------------------------------

/// Upcoming device-calendar events, today through the next two years.
final upcomingCalendarEventsProvider =
    FutureProvider.autoDispose<List<CalendarEvent>>((ref) {
      final today = CountdownCalculator.dateOnly(DateTime.now());
      return ref
          .read(deviceCalendarServiceProvider)
          .events(
            from: today,
            to: DateTime(today.year + 2, today.month, today.day),
          );
    });
