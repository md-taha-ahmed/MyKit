import 'package:flutter/material.dart';

const _palette = <int>[
  0xFF000000,
  0xFF212121,
  0xFF424242,
  0xFF757575,
  0xFFBDBDBD,
  0xFFFFFFFF,
  0xFFB71C1C,
  0xFFE53935,
  0xFFFF7043,
  0xFFFF9800,
  0xFFFFC107,
  0xFFFFEB3B,
  0xFF1B5E20,
  0xFF43A047,
  0xFF66BB6A,
  0xFF1DE9B6,
  0xFF00897B,
  0xFF006064,
  0xFF0D47A1,
  0xFF1E88E5,
  0xFF29B6F6,
  0xFF1A9CD8,
  0xFF3F51B5,
  0xFF1A237E,
  0xFF4A148C,
  0xFF7B1FA2,
  0xFF9C27B0,
  0xFFBA68C8,
  0xFFEC407A,
  0xFFF8BBD0,
  0xFF3E2723,
  0xFF6D4C41,
  0xFF0D1B2A,
  0xFF263238,
  0xFF607D8B,
  0xFFCFD8DC,
];

/// Shows a palette and returns the picked ARGB color, or null if dismissed.
Future<int?> showColorPickerSheet(
  BuildContext context, {
  required String title,
  required int selected,
}) {
  return showModalBottomSheet<int>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 6,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final color in _palette)
                  ColorDot(
                    color: color,
                    selected: color == selected,
                    onTap: () => Navigator.pop(context, color),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class ColorDot extends StatelessWidget {
  const ColorDot({
    super.key,
    required this.color,
    this.selected = false,
    this.size = 48,
    this.onTap,
  });

  final int color;
  final bool selected;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return InkResponse(
      onTap: onTap,
      radius: size / 2 + 4,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Color(color),
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? accent : const Color(0xFF8A8A8E),
            width: selected ? 3 : 1,
          ),
        ),
      ),
    );
  }
}
