import 'package:flutter/material.dart';

import '../../domain/entities/fitness_entities.dart';
import '../providers/fitness_providers.dart';

/// Front and back body outline with the trained muscles highlighted:
/// primary in full colour, secondary lighter. Muscle names match the
/// exercise database.
class BodyDiagram extends StatelessWidget {
  const BodyDiagram({
    super.key,
    this.primary = const {},
    this.secondary = const {},
    this.height = 260,
    this.showLegend = true,
  });

  final Set<String> primary;
  final Set<String> secondary;
  final double height;
  final bool showLegend;

  @override
  Widget build(BuildContext context) {
    Widget figure(bool front) => Column(
      children: [
        SizedBox(
          height: height,
          width: height * 100 / 220,
          child: CustomPaint(
            painter: _BodyPainter(
              front: front,
              primary: primary,
              secondary: secondary,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          front ? 'Front' : 'Back',
          style: const TextStyle(fontSize: 12, color: Colors.white54),
        ),
      ],
    );

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [figure(true), figure(false)],
        ),
        if (showLegend && (primary.isNotEmpty || secondary.isNotEmpty)) ...[
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final m in primary) _chip(m, true),
              for (final m in secondary.difference(primary)) _chip(m, false),
            ],
          ),
        ],
      ],
    );
  }

  Widget _chip(String muscle, bool primary) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: fitnessAccent.withValues(alpha: primary ? 0.85 : 0.3),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      '${Muscle.label(muscle)}${primary ? '' : ' (helps)'}',
      style: TextStyle(
        fontSize: 12,
        color: primary ? Colors.black : Colors.white,
        fontWeight: primary ? FontWeight.w600 : FontWeight.normal,
      ),
    ),
  );
}

/// A shape in a 100 × 220 box, optionally belonging to a muscle.
typedef _Part = ({String? muscle, Path path});

class _BodyPainter extends CustomPainter {
  _BodyPainter({
    required this.front,
    required this.primary,
    required this.secondary,
  });

  final bool front;
  final Set<String> primary;
  final Set<String> secondary;

  static Path _oval(double cx, double cy, double rx, double ry) => Path()
    ..addOval(
      Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2),
    );

  static Path _rr(double x, double y, double w, double h, double r) => Path()
    ..addRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r)),
    );

  static Path _poly(List<Offset> points) => Path()..addPolygon(points, true);

  /// Silhouette shared by both views.
  static final List<Path> _base = [
    _oval(50, 14, 10, 11), // head
    _rr(45, 23, 10, 9, 3), // neck
    _rr(31, 30, 38, 58, 11), // torso
    _rr(34, 82, 32, 20, 8), // hips
    _rr(19, 32, 12, 52, 6), // left upper arm + forearm
    _rr(69, 32, 12, 52, 6),
    _rr(16, 66, 11, 30, 5), // forearms
    _rr(73, 66, 11, 30, 5),
    _oval(19, 99, 4.5, 5.5), // hands
    _oval(81, 99, 4.5, 5.5),
    _rr(35, 96, 14, 54, 7), // thighs
    _rr(51, 96, 14, 54, 7),
    _rr(36, 148, 12, 52, 6), // lower legs
    _rr(52, 148, 12, 52, 6),
    _rr(35, 198, 13, 8, 4), // feet
    _rr(52, 198, 13, 8, 4),
  ];

  static final List<_Part> _frontParts = [
    (muscle: Muscle.neck, path: _rr(46, 23, 8, 8, 3)),
    (
      muscle: Muscle.traps,
      path: _poly(const [Offset(38, 31), Offset(46, 25), Offset(46, 32)]),
    ),
    (
      muscle: Muscle.traps,
      path: _poly(const [Offset(62, 31), Offset(54, 25), Offset(54, 32)]),
    ),
    (muscle: Muscle.shoulders, path: _oval(29, 38, 8, 7.5)),
    (muscle: Muscle.shoulders, path: _oval(71, 38, 8, 7.5)),
    (muscle: Muscle.chest, path: _rr(34, 33, 15.5, 17, 7)),
    (muscle: Muscle.chest, path: _rr(50.5, 33, 15.5, 17, 7)),
    (muscle: Muscle.abdominals, path: _rr(41, 52, 18, 33, 6)),
    (muscle: Muscle.biceps, path: _oval(25, 55, 5.2, 10.5)),
    (muscle: Muscle.biceps, path: _oval(75, 55, 5.2, 10.5)),
    (muscle: Muscle.forearms, path: _oval(21.5, 79, 4.6, 11)),
    (muscle: Muscle.forearms, path: _oval(78.5, 79, 4.6, 11)),
    (muscle: Muscle.abductors, path: _oval(35.5, 96, 3.2, 8)),
    (muscle: Muscle.abductors, path: _oval(64.5, 96, 3.2, 8)),
    (muscle: Muscle.quadriceps, path: _rr(36.5, 100, 11, 44, 6)),
    (muscle: Muscle.quadriceps, path: _rr(52.5, 100, 11, 44, 6)),
    (muscle: Muscle.adductors, path: _rr(46, 100, 3.5, 24, 2)),
    (muscle: Muscle.adductors, path: _rr(50.5, 100, 3.5, 24, 2)),
    (muscle: Muscle.calves, path: _oval(39.5, 166, 3.5, 13)),
    (muscle: Muscle.calves, path: _oval(60.5, 166, 3.5, 13)),
  ];

  static final List<_Part> _backParts = [
    (muscle: Muscle.neck, path: _rr(46, 23, 8, 8, 3)),
    (
      muscle: Muscle.traps,
      path: _poly(const [
        Offset(50, 24),
        Offset(65, 34),
        Offset(56, 42),
        Offset(50, 52),
        Offset(44, 42),
        Offset(35, 34),
      ]),
    ),
    (muscle: Muscle.shoulders, path: _oval(29, 38, 8, 7.5)),
    (muscle: Muscle.shoulders, path: _oval(71, 38, 8, 7.5)),
    (muscle: Muscle.middleBack, path: _rr(41, 44, 18, 22, 5)),
    (
      muscle: Muscle.lats,
      path: _poly(const [
        Offset(33, 42),
        Offset(41, 46),
        Offset(42, 74),
        Offset(36, 70),
      ]),
    ),
    (
      muscle: Muscle.lats,
      path: _poly(const [
        Offset(67, 42),
        Offset(59, 46),
        Offset(58, 74),
        Offset(64, 70),
      ]),
    ),
    (muscle: Muscle.lowerBack, path: _rr(43, 68, 14, 17, 5)),
    (muscle: Muscle.triceps, path: _oval(25, 55, 5.2, 10.5)),
    (muscle: Muscle.triceps, path: _oval(75, 55, 5.2, 10.5)),
    (muscle: Muscle.forearms, path: _oval(21.5, 79, 4.6, 11)),
    (muscle: Muscle.forearms, path: _oval(78.5, 79, 4.6, 11)),
    (muscle: Muscle.abductors, path: _oval(35.5, 92, 3.2, 7)),
    (muscle: Muscle.abductors, path: _oval(64.5, 92, 3.2, 7)),
    (muscle: Muscle.glutes, path: _oval(43, 95, 8, 9.5)),
    (muscle: Muscle.glutes, path: _oval(57, 95, 8, 9.5)),
    (muscle: Muscle.hamstrings, path: _rr(36.5, 106, 11, 40, 6)),
    (muscle: Muscle.hamstrings, path: _rr(52.5, 106, 11, 40, 6)),
    (muscle: Muscle.adductors, path: _rr(46.5, 106, 3, 18, 2)),
    (muscle: Muscle.adductors, path: _rr(50.5, 106, 3, 18, 2)),
    (muscle: Muscle.calves, path: _oval(42, 164, 5.5, 14)),
    (muscle: Muscle.calves, path: _oval(58, 164, 5.5, 14)),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.height / 220;
    canvas.save();
    canvas.translate((size.width - 100 * scale) / 2, 0);
    canvas.scale(scale);

    final base = Paint()..color = const Color(0xFF34343B);
    for (final p in _base) {
      canvas.drawPath(p, base);
    }

    final idle = Paint()..color = const Color(0xFF45454E);
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = const Color(0xFF1F1F24);
    final strong = Paint()..color = fitnessAccent;
    final light = Paint()..color = fitnessAccent.withValues(alpha: 0.42);

    for (final part in front ? _frontParts : _backParts) {
      final m = part.muscle;
      final paint = m != null && primary.contains(m)
          ? strong
          : m != null && secondary.contains(m)
          ? light
          : idle;
      canvas.drawPath(part.path, paint);
      canvas.drawPath(part.path, outline);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BodyPainter old) =>
      old.front != front ||
      old.primary != primary ||
      old.secondary != secondary;
}
