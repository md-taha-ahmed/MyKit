/// A preset color combination for a countdown ring.
class CountdownTheme {
  const CountdownTheme({
    required this.name,
    required this.ringColor,
    required this.backgroundColor,
    required this.trackColor,
    required this.textColor,
  });

  final String name;
  final int ringColor;
  final int backgroundColor;
  final int trackColor;
  final int textColor;

  static const presets = <CountdownTheme>[
    CountdownTheme(
      name: 'Midnight purple',
      ringColor: 0xFF7B1FA2,
      backgroundColor: 0xFF000000,
      trackColor: 0xFF000000,
      textColor: 0xFFFFFFFF,
    ),
    CountdownTheme(
      name: 'Ocean',
      ringColor: 0xFF29B6F6,
      backgroundColor: 0xFF0D1B2A,
      trackColor: 0xFF1B3A57,
      textColor: 0xFFFFFFFF,
    ),
    CountdownTheme(
      name: 'Sunset',
      ringColor: 0xFFFF7043,
      backgroundColor: 0xFF2B1B17,
      trackColor: 0xFF4E342E,
      textColor: 0xFFFFE0B2,
    ),
    CountdownTheme(
      name: 'Forest',
      ringColor: 0xFF66BB6A,
      backgroundColor: 0xFF0F1F12,
      trackColor: 0xFF1F3B24,
      textColor: 0xFFE8F5E9,
    ),
    CountdownTheme(
      name: 'Paper',
      ringColor: 0xFF212121,
      backgroundColor: 0xFFFFFFFF,
      trackColor: 0xFFE0E0E0,
      textColor: 0xFF212121,
    ),
    CountdownTheme(
      name: 'Rose',
      ringColor: 0xFFEC407A,
      backgroundColor: 0xFF1A0A10,
      trackColor: 0xFF3D1526,
      textColor: 0xFFFCE4EC,
    ),
    CountdownTheme(
      name: 'Gold',
      ringColor: 0xFFFFC107,
      backgroundColor: 0xFF111111,
      trackColor: 0xFF333333,
      textColor: 0xFFFFC107,
    ),
    CountdownTheme(
      name: 'Mint',
      ringColor: 0xFF1DE9B6,
      backgroundColor: 0xFF263238,
      trackColor: 0xFF37474F,
      textColor: 0xFFFFFFFF,
    ),
  ];
}
