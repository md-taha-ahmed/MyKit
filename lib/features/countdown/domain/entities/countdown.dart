import 'countdown_enums.dart';

/// A countdown to a calendar day. Colors are stored as ARGB ints so the
/// domain layer stays free of Flutter imports.
class Countdown {
  const Countdown({
    required this.id,
    required this.targetDate,
    required this.createdAt,
    this.title = '',
    this.notes = '',
    this.recurrence = Recurrence.none,
    this.showTitleInWidget = true,
    this.unit = CountUnit.days,
    this.showLabel = true,
    this.decreaseCircle = true,
    this.decreaseStartDays = 30,
    this.ringColor = 0xFF7B1FA2,
    this.backgroundColor = 0xFF000000,
    this.trackColor = 0xFF000000,
    this.textColor = 0xFFFFFFFF,
    this.font = CountdownFont.normal,
    this.dropShadow = false,
    this.clockwise = false,
  });

  final String id;

  /// Date-only (time component is always midnight). Widgets cannot show time.
  final DateTime targetDate;
  final DateTime createdAt;
  final String title;
  final String notes;
  final Recurrence recurrence;
  final bool showTitleInWidget;
  final CountUnit unit;
  final bool showLabel;

  /// When true the ring shrinks as the deadline gets closer.
  final bool decreaseCircle;

  /// How many days before the deadline the ring starts shrinking.
  final int decreaseStartDays;

  final int ringColor;
  final int backgroundColor;
  final int trackColor;
  final int textColor;
  final CountdownFont font;
  final bool dropShadow;
  final bool clockwise;

  Countdown copyWith({
    DateTime? targetDate,
    String? title,
    String? notes,
    Recurrence? recurrence,
    bool? showTitleInWidget,
    CountUnit? unit,
    bool? showLabel,
    bool? decreaseCircle,
    int? decreaseStartDays,
    int? ringColor,
    int? backgroundColor,
    int? trackColor,
    int? textColor,
    CountdownFont? font,
    bool? dropShadow,
    bool? clockwise,
  }) {
    return Countdown(
      id: id,
      createdAt: createdAt,
      targetDate: targetDate ?? this.targetDate,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      recurrence: recurrence ?? this.recurrence,
      showTitleInWidget: showTitleInWidget ?? this.showTitleInWidget,
      unit: unit ?? this.unit,
      showLabel: showLabel ?? this.showLabel,
      decreaseCircle: decreaseCircle ?? this.decreaseCircle,
      decreaseStartDays: decreaseStartDays ?? this.decreaseStartDays,
      ringColor: ringColor ?? this.ringColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      trackColor: trackColor ?? this.trackColor,
      textColor: textColor ?? this.textColor,
      font: font ?? this.font,
      dropShadow: dropShadow ?? this.dropShadow,
      clockwise: clockwise ?? this.clockwise,
    );
  }
}
