enum CountUnit {
  days('Days', 'Day'),
  weeks('Weeks', 'Week'),
  months('Months', 'Month'),
  years('Years', 'Year');

  const CountUnit(this.label, this.singularLabel);

  final String label;
  final String singularLabel;
}

enum Recurrence {
  none('Does not repeat'),
  daily('Every day'),
  weekly('Every week'),
  monthly('Every month'),
  yearly('Every year');

  const Recurrence(this.label);

  final String label;
}

/// Fonts available both in Flutter and in the native Android widget renderer.
enum CountdownFont {
  normal('Default', null),
  serif('Serif', 'serif'),
  monospace('Monospace', 'monospace'),
  condensed('Condensed', 'sans-serif-condensed');

  const CountdownFont(this.label, this.family);

  final String label;

  /// Android system font family name (null = platform default).
  final String? family;
}

T enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}
