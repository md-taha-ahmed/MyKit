import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n.dart';
import '../../domain/entities/fitness_entities.dart';
import '../providers/fitness_providers.dart';

/// Anatomical front/back figure with muscles highlighted.
///
/// Either [primary]/[secondary] (an exercise: full / light colour), or
/// [intensity] 0–1 per muscle (a heat map, e.g. sets trained this week).
/// Muscle names match the exercise database.
class BodyDiagram extends StatelessWidget {
  const BodyDiagram({
    super.key,
    this.primary = const {},
    this.secondary = const {},
    this.intensity,
    this.height = 280,
    this.showLegend = true,
  });

  final Set<String> primary;
  final Set<String> secondary;
  final Map<String, double>? intensity;
  final double height;
  final bool showLegend;

  double _level(String muscle) {
    final heat = intensity;
    if (heat != null) return (heat[muscle] ?? 0).clamp(0.0, 1.0);
    if (primary.contains(muscle)) return 1;
    if (secondary.contains(muscle)) return 0.45;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    Widget figure(bool front) => Column(
      children: [
        SizedBox(
          height: height,
          width: height * 100 / 214,
          child: CustomPaint(
            painter: _BodyPainter(front: front, level: _level),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          front ? tr('Front') : tr('Back'),
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
        if (showLegend &&
            intensity == null &&
            (primary.isNotEmpty || secondary.isNotEmpty)) ...[
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

/// A muscle shape on the left half of a 100 × 214 figure (mirrored for the
/// right side).
typedef _Muscle = ({String muscle, Path path});

class _BodyPainter extends CustomPainter {
  _BodyPainter({required this.front, required this.level});

  final bool front;
  final double Function(String muscle) level;

  // ---- Shapes --------------------------------------------------------------

  /// Left half of the silhouette, closed along the centre line.
  static final Path _halfBody = Path()
    ..moveTo(50.6, 24)
    ..lineTo(46, 24)
    ..cubicTo(46, 26.5, 46, 28.5, 45.5, 30)
    ..cubicTo(40, 31, 33, 31.5, 28, 33.5)
    ..cubicTo(22, 35.5, 19, 40.5, 18.8, 47)
    ..cubicTo(18.2, 53, 17.8, 59, 17.6, 64)
    ..cubicTo(17, 68, 16.2, 71, 15.6, 74)
    ..cubicTo(14.8, 82, 14.8, 89, 15.6, 96)
    ..cubicTo(15.6, 99, 15.4, 102, 16.6, 105)
    ..cubicTo(17.8, 108.5, 21.6, 108.5, 22.4, 104.5)
    ..cubicTo(22.6, 102, 22.6, 99, 22.8, 96.5)
    ..cubicTo(23.8, 89, 25, 81, 25.4, 74.5)
    ..cubicTo(25.8, 70.5, 26.6, 67, 27.2, 62)
    ..cubicTo(27.6, 58, 28, 54, 28.6, 50)
    ..cubicTo(30, 57, 31.2, 64, 31.8, 72)
    ..cubicTo(32.4, 79, 32.6, 85, 31.6, 91)
    ..cubicTo(30.8, 98, 31.4, 106, 32.4, 116)
    ..cubicTo(33.2, 128, 34.6, 139, 35.6, 147)
    ..cubicTo(35.8, 151, 34.8, 156, 34.6, 162)
    ..cubicTo(34.6, 172, 36.4, 183, 37.6, 194)
    ..cubicTo(37.4, 198, 34.8, 201, 35.2, 204)
    ..cubicTo(36, 206, 44, 206, 46.4, 205)
    ..cubicTo(47, 202, 46.2, 198, 45.8, 194)
    ..cubicTo(45.6, 184, 47, 174, 46.6, 164)
    ..cubicTo(46.4, 157, 47, 151, 47.2, 147)
    ..cubicTo(47.6, 137, 48.4, 125, 49, 117)
    ..cubicTo(49.4, 114, 50, 112, 50.6, 111)
    ..close();

  static Path _p(void Function(Path) draw) => Path()..also(draw);

  static final List<_Muscle> _front = [
    (
      muscle: Muscle.neck,
      path: _p(
        (p) => p
          ..moveTo(46.6, 24.5)
          ..cubicTo(47.5, 27, 48.6, 29, 50.6, 30)
          ..lineTo(50.6, 24.5)
          ..close(),
      ),
    ),
    (
      muscle: Muscle.traps,
      path: _p(
        (p) => p
          ..moveTo(45.6, 29.6)
          ..cubicTo(42, 31, 37, 32, 33, 33.2)
          ..cubicTo(37.5, 33.8, 42.5, 33.4, 46.2, 32)
          ..close(),
      ),
    ),
    (
      muscle: Muscle.shoulders,
      path: _p(
        (p) => p
          ..moveTo(31, 34.2)
          ..cubicTo(24, 35.2, 19.8, 40, 19.6, 47.5)
          ..cubicTo(19.6, 50, 20.6, 51.5, 22, 50.5)
          ..cubicTo(25, 47.5, 28.2, 43.5, 30.4, 39.8)
          ..cubicTo(31.4, 38, 31.6, 36, 31, 34.2)
          ..close(),
      ),
    ),
    (
      muscle: Muscle.chest,
      path: _p(
        (p) => p
          ..moveTo(32, 36.5)
          ..cubicTo(37, 34.5, 44.5, 34.4, 49.6, 35.5)
          ..lineTo(49.6, 47.5)
          ..cubicTo(45, 51.2, 37.5, 51.4, 32.4, 47.8)
          ..cubicTo(30.6, 45.5, 30.4, 40, 32, 36.5)
          ..close(),
      ),
    ),
    (
      muscle: Muscle.biceps,
      path: _p(
        (p) => p
          ..moveTo(21.2, 51.6)
          ..cubicTo(20.8, 57, 21.4, 62.5, 23, 66.4)
          ..cubicTo(25.2, 66.6, 27, 62.6, 27.4, 57.5)
          ..cubicTo(27.6, 54, 26.8, 51, 25, 50)
          ..cubicTo(23.4, 49.6, 21.8, 50.2, 21.2, 51.6)
          ..close(),
      ),
    ),
    (
      muscle: Muscle.forearms,
      path: _p(
        (p) => p
          ..moveTo(17.2, 71.5)
          ..cubicTo(15.8, 79, 16.2, 88, 17.4, 95.5)
          ..cubicTo(19.4, 96, 21.4, 92.5, 22.6, 87)
          ..cubicTo(23.8, 81, 24.8, 75, 25, 70.4)
          ..cubicTo(22.4, 68.6, 19.2, 69.2, 17.2, 71.5)
          ..close(),
      ),
    ),
    // Six-pack (three blocks per side) and the obliques.
    for (final (top, bottom) in const [
      (52.2, 59.4),
      (60.6, 67.8),
      (69.0, 76.6),
    ])
      (
        muscle: Muscle.abdominals,
        path: _p(
          (p) => p.addRRect(
            RRect.fromLTRBR(
              43.2,
              top,
              49.4,
              bottom,
              const Radius.circular(2.4),
            ),
          ),
        ),
      ),
    (
      muscle: Muscle.abdominals,
      path: _p(
        (p) => p
          ..moveTo(43.4, 78)
          ..lineTo(49.4, 78)
          ..lineTo(49.4, 92)
          ..cubicTo(47, 90, 44.6, 85, 43.4, 78)
          ..close(),
      ),
    ),
    (
      muscle: Muscle.abdominals,
      path: _p(
        (p) => p
          ..moveTo(33.4, 54)
          ..cubicTo(36.6, 53, 40, 53.4, 42.2, 55)
          ..lineTo(42.2, 79)
          ..cubicTo(40, 82.5, 37.4, 86, 33.8, 87.6)
          ..cubicTo(33.4, 77, 33.2, 64, 33.4, 54)
          ..close(),
      ),
    ),
    (
      muscle: Muscle.abductors,
      path: _p(
        (p) => p
          ..moveTo(32.2, 92)
          ..cubicTo(31.4, 99, 32, 105, 33.4, 110)
          ..cubicTo(35, 106, 36.4, 100, 36.2, 94.5)
          ..cubicTo(35, 93, 33.6, 92.2, 32.2, 92)
          ..close(),
      ),
    ),
    // Quads: outer head, middle head, inner teardrop.
    (
      muscle: Muscle.quadriceps,
      path: _p(
        (p) => p
          ..moveTo(33.8, 110)
          ..cubicTo(33.6, 122, 34.8, 135, 37, 145.6)
          ..cubicTo(39, 146.4, 40.4, 143.4, 40.4, 138.5)
          ..cubicTo(40.4, 127, 39, 115, 36.8, 104)
          ..close(),
      ),
    ),
    (
      muscle: Muscle.quadriceps,
      path: _p(
        (p) => p
          ..moveTo(37.8, 101)
          ..cubicTo(40.4, 113, 42, 125, 42.2, 140)
          ..cubicTo(43.6, 141.6, 45.6, 140, 46, 135.6)
          ..cubicTo(46.6, 124, 45.6, 112, 42.8, 99.6)
          ..cubicTo(41, 99, 39, 99.6, 37.8, 101)
          ..close(),
      ),
    ),
    (
      muscle: Muscle.quadriceps,
      path: _p(
        (p) => p
          ..moveTo(44.2, 130.5)
          ..cubicTo(47.4, 134, 48.2, 140, 46.2, 146)
          ..cubicTo(43.4, 146.4, 42.2, 142.4, 42.8, 137.6)
          ..cubicTo(43.2, 134.6, 43.6, 132.4, 44.2, 130.5)
          ..close(),
      ),
    ),
    (
      muscle: Muscle.adductors,
      path: _p(
        (p) => p
          ..moveTo(46, 108)
          ..cubicTo(47.4, 115, 48.2, 121, 48.6, 128)
          ..cubicTo(49.4, 122, 49.8, 116, 50.2, 112)
          ..cubicTo(48.8, 110, 47.4, 108.6, 46, 108)
          ..close(),
      ),
    ),
    (
      muscle: Muscle.calves,
      path: _p(
        (p) => p
          ..moveTo(35.6, 154)
          ..cubicTo(34.8, 162, 35.6, 171, 37.8, 178)
          ..cubicTo(39.4, 172, 39.8, 163, 38.8, 154.6)
          ..cubicTo(37.8, 153.4, 36.6, 153.2, 35.6, 154)
          ..close(),
      ),
    ),
    (
      muscle: Muscle.calves,
      path: _p(
        (p) => p
          ..moveTo(45.4, 154.4)
          ..cubicTo(46.8, 162, 46.4, 171, 44.4, 177.6)
          ..cubicTo(43, 171, 42.8, 162, 43.6, 155)
          ..cubicTo(44.2, 154, 44.8, 154, 45.4, 154.4)
          ..close(),
      ),
    ),
  ];

  static final List<_Muscle> _back = [
    (
      muscle: Muscle.neck,
      path: _p(
        (p) => p
          ..moveTo(46.4, 24.5)
          ..cubicTo(47, 26.5, 47.4, 28, 47.6, 29.4)
          ..lineTo(50.6, 29.4)
          ..lineTo(50.6, 24.5)
          ..close(),
      ),
    ),
    (
      muscle: Muscle.traps,
      path: _p(
        (p) => p
          ..moveTo(50.6, 25.5)
          ..cubicTo(48.6, 28.6, 44, 30.6, 36, 32)
          ..cubicTo(32.6, 32.6, 30.6, 33.4, 29.6, 35)
          ..cubicTo(35, 36.6, 41, 39, 44.6, 44)
          ..cubicTo(46.8, 48, 48.6, 54, 50.6, 60)
          ..close(),
      ),
    ),
    (
      muscle: Muscle.shoulders,
      path: _p(
        (p) => p
          ..moveTo(29.4, 35.4)
          ..cubicTo(23.4, 36.4, 19.8, 41, 19.6, 47.6)
          ..cubicTo(19.6, 50, 20.8, 51.4, 22.2, 50.4)
          ..cubicTo(25.6, 47.6, 28.8, 43.4, 31, 38.8)
          ..cubicTo(30.6, 37.4, 30.2, 36.2, 29.4, 35.4)
          ..close(),
      ),
    ),
    // Upper back: infraspinatus / teres and the rhomboids by the spine.
    (
      muscle: Muscle.middleBack,
      path: _p(
        (p) => p
          ..moveTo(31.8, 39)
          ..cubicTo(36.4, 39.6, 41.2, 42.4, 43.8, 46.6)
          ..cubicTo(42.8, 51.4, 38.8, 54.4, 34, 53.4)
          ..cubicTo(32.2, 49.6, 31.4, 44, 31.8, 39)
          ..close(),
      ),
    ),
    (
      muscle: Muscle.middleBack,
      path: _p(
        (p) => p
          ..moveTo(45.4, 45)
          ..cubicTo(47.4, 50, 48.8, 56, 50, 62)
          ..lineTo(50, 66)
          ..cubicTo(47.6, 62, 45.6, 56, 44.6, 50)
          ..close(),
      ),
    ),
    (
      muscle: Muscle.lats,
      path: _p(
        (p) => p
          ..moveTo(30.8, 47.6)
          ..cubicTo(34.6, 55.6, 40, 61, 45.8, 64.6)
          ..cubicTo(46.6, 71, 44.8, 78.6, 41.2, 83.4)
          ..cubicTo(37.4, 80.4, 34.4, 74.6, 32.4, 67.6)
          ..cubicTo(31.2, 61, 30.4, 54, 30.8, 47.6)
          ..close(),
      ),
    ),
    (
      muscle: Muscle.lowerBack,
      path: _p(
        (p) => p
          ..moveTo(46.4, 66)
          ..cubicTo(48.4, 72, 49.4, 80, 49.4, 90)
          ..lineTo(44.4, 90)
          ..cubicTo(43.8, 82, 44.2, 73, 46.4, 66)
          ..close(),
      ),
    ),
    (
      muscle: Muscle.triceps,
      path: _p(
        (p) => p
          ..moveTo(21.2, 50.6)
          ..cubicTo(20.4, 56.6, 21, 62.6, 22.8, 66.6)
          ..cubicTo(25.4, 64.8, 27.4, 59, 27.6, 53)
          ..cubicTo(25.8, 50.6, 23.4, 49.6, 21.2, 50.6)
          ..close(),
      ),
    ),
    (
      muscle: Muscle.forearms,
      path: _p(
        (p) => p
          ..moveTo(17.2, 71.5)
          ..cubicTo(15.8, 79, 16.2, 88, 17.4, 95.5)
          ..cubicTo(19.4, 96, 21.4, 92.5, 22.6, 87)
          ..cubicTo(23.8, 81, 24.8, 75, 25, 70.4)
          ..cubicTo(22.4, 68.6, 19.2, 69.2, 17.2, 71.5)
          ..close(),
      ),
    ),
    (
      muscle: Muscle.abductors,
      path: _p(
        (p) => p
          ..moveTo(31.8, 86.6)
          ..cubicTo(31, 90.6, 31.4, 94.6, 32.4, 97.6)
          ..cubicTo(34.8, 93.6, 38.4, 90.6, 42.4, 89.6)
          ..cubicTo(38.6, 87.2, 35, 86.4, 31.8, 86.6)
          ..close(),
      ),
    ),
    (
      muscle: Muscle.glutes,
      path: _p(
        (p) => p
          ..moveTo(32.8, 96)
          ..cubicTo(32, 103, 34.6, 110, 41.2, 113)
          ..cubicTo(45.6, 114.4, 48.8, 112.4, 50.2, 108.6)
          ..lineTo(50.2, 93.4)
          ..cubicTo(45.4, 90, 37.6, 90, 32.8, 96)
          ..close(),
      ),
    ),
    (
      muscle: Muscle.hamstrings,
      path: _p(
        (p) => p
          ..moveTo(33.8, 115.4)
          ..cubicTo(33.6, 127, 35.4, 138, 38.6, 146.6)
          ..cubicTo(41.4, 146.6, 43, 142.4, 43, 135)
          ..cubicTo(43, 125, 41.4, 117, 39.4, 113.4)
          ..close(),
      ),
    ),
    (
      muscle: Muscle.hamstrings,
      path: _p(
        (p) => p
          ..moveTo(41, 114.6)
          ..cubicTo(44, 124, 45.6, 134, 45.6, 144.6)
          ..cubicTo(47.6, 144.6, 48.6, 138.6, 48.8, 129)
          ..cubicTo(48.8, 121, 47.4, 116, 44.6, 113.4)
          ..close(),
      ),
    ),
    (
      muscle: Muscle.adductors,
      path: _p(
        (p) => p
          ..moveTo(46.6, 113.6)
          ..cubicTo(48, 117, 49.2, 121, 49.8, 125)
          ..lineTo(50.2, 113.4)
          ..close(),
      ),
    ),
    // Calves: the two heads of the gastrocnemius.
    (
      muscle: Muscle.calves,
      path: _p(
        (p) => p
          ..moveTo(36.4, 151.6)
          ..cubicTo(34.2, 159, 34.8, 169, 38.8, 178)
          ..cubicTo(41, 173, 41.8, 165, 41.2, 156)
          ..cubicTo(40.4, 152.6, 38.4, 151, 36.4, 151.6)
          ..close(),
      ),
    ),
    (
      muscle: Muscle.calves,
      path: _p(
        (p) => p
          ..moveTo(41.8, 153.2)
          ..cubicTo(45.4, 151.4, 47.4, 155.6, 46.8, 163.6)
          ..cubicTo(46.4, 170, 44.6, 176, 42.6, 179.4)
          ..cubicTo(42.4, 170, 42.6, 161, 41.8, 153.2)
          ..close(),
      ),
    ),
  ];

  // ---- Painting ------------------------------------------------------------

  static const _skinTop = Color(0xFF3E3E47);
  static const _skinBottom = Color(0xFF2C2C33);
  static const _idle = Color(0xFF4C4C57);
  static const _outline = Color(0xFF1B1B20);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.height / 214;
    canvas.save();
    canvas.translate((size.width - 100 * scale) / 2, 0);
    canvas.scale(scale);

    final bounds = const Rect.fromLTWH(0, 0, 100, 214);
    final skin = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [_skinTop, _skinBottom],
      ).createShader(bounds);

    void bothSides(void Function() draw) {
      draw();
      canvas.save();
      canvas.translate(100, 0);
      canvas.scale(-1, 1);
      draw();
      canvas.restore();
    }

    // Head and body.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(50, 13), width: 18.4, height: 22),
      skin,
    );
    bothSides(() => canvas.drawPath(_halfBody, skin));

    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = _outline;
    final glow = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.6);

    final muscles = front ? _front : _back;
    // Glow first so it sits under every muscle.
    bothSides(() {
      for (final m in muscles) {
        final l = level(m.muscle);
        if (l < 0.6) continue;
        glow.color = fitnessAccent.withValues(alpha: 0.35 * l);
        canvas.drawPath(m.path, glow);
      }
    });
    bothSides(() {
      for (final m in muscles) {
        final l = level(m.muscle);
        final color = l <= 0
            ? _idle
            : Color.lerp(_idle, fitnessAccent, 0.25 + 0.75 * l)!;
        final rect = m.path.getBounds();
        final fill = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(color, Colors.white, 0.12)!,
              Color.lerp(color, Colors.black, 0.18)!,
            ],
          ).createShader(rect);
        canvas.drawPath(m.path, fill);
        canvas.drawPath(m.path, outline);
      }
    });

    // Centre line (sternum / spine) for definition.
    final line = Paint()
      ..color = _outline
      ..strokeWidth = 0.6;
    canvas.drawLine(
      Offset(50, front ? 35.5 : 30),
      Offset(50, front ? 90 : 92),
      line,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BodyPainter old) => true;
}

extension<T> on T {
  T also(void Function(T) f) {
    f(this);
    return this;
  }
}
