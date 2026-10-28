import '../../domain/entities/countdown.dart';
import '../../domain/entities/countdown_enums.dart';

/// JSON mapping for [Countdown].
///
/// This exact format is also read by the native Android widget
/// (`CountdownWidgetProvider.kt`), so treat key names as a public contract.
abstract final class CountdownModel {
  static Map<String, dynamic> toJson(Countdown c) => {
    'id': c.id,
    'title': c.title,
    'notes': c.notes,
    'targetDate': _formatDate(c.targetDate),
    'createdAt': c.createdAt.toIso8601String(),
    'recurrence': c.recurrence.name,
    'showTitleInWidget': c.showTitleInWidget,
    'unit': c.unit.name,
    'showLabel': c.showLabel,
    'decreaseCircle': c.decreaseCircle,
    'decreaseStartDays': c.decreaseStartDays,
    'ringColor': c.ringColor,
    'backgroundColor': c.backgroundColor,
    'trackColor': c.trackColor,
    'textColor': c.textColor,
    'font': c.font.name,
    'dropShadow': c.dropShadow,
    'clockwise': c.clockwise,
  };

  static Countdown fromJson(Map<String, dynamic> json) {
    final d = _defaults;
    return Countdown(
      id: json['id'] as String,
      title: json['title'] as String? ?? d.title,
      notes: json['notes'] as String? ?? d.notes,
      targetDate: DateTime.parse(json['targetDate'] as String),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      recurrence: enumByName(
        Recurrence.values,
        json['recurrence'],
        d.recurrence,
      ),
      showTitleInWidget:
          json['showTitleInWidget'] as bool? ?? d.showTitleInWidget,
      unit: enumByName(CountUnit.values, json['unit'], d.unit),
      showLabel: json['showLabel'] as bool? ?? d.showLabel,
      decreaseCircle: json['decreaseCircle'] as bool? ?? d.decreaseCircle,
      decreaseStartDays:
          json['decreaseStartDays'] as int? ?? d.decreaseStartDays,
      ringColor: json['ringColor'] as int? ?? d.ringColor,
      backgroundColor: json['backgroundColor'] as int? ?? d.backgroundColor,
      trackColor: json['trackColor'] as int? ?? d.trackColor,
      textColor: json['textColor'] as int? ?? d.textColor,
      font: enumByName(CountdownFont.values, json['font'], d.font),
      dropShadow: json['dropShadow'] as bool? ?? d.dropShadow,
      clockwise: json['clockwise'] as bool? ?? d.clockwise,
    );
  }

  /// Source of default values for keys missing from older saved data.
  static final _defaults = Countdown(
    id: '',
    targetDate: DateTime(2000),
    createdAt: DateTime(2000),
  );

  static String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
