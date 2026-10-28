import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/entities/countdown.dart';
import '../../domain/services/countdown_calculator.dart';

/// The circular countdown, exactly as it appears on the home-screen widget.
///
/// Geometry matches `CountdownRenderer.kt` so the in-app preview is faithful.
class CountdownRing extends StatelessWidget {
  const CountdownRing({
    super.key,
    required this.countdown,
    this.size = 120,
    this.now,
  });

  final Countdown countdown;
  final double size;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final snap = CountdownCalculator.snapshot(countdown, now: now);
    final textColor = Color(countdown.textColor);
    final shadows = countdown.dropShadow
        ? [
            Shadow(
              color: Colors.black.withValues(alpha: .6),
              blurRadius: size * .03,
              offset: Offset(0, size * .012),
            ),
          ]
        : null;

    // Inner area available for text.
    final inner = size * (1 - 2 * _RingPainter.strokeRatio) * .78;

    // Own (transparent) Material: during the Hero flight between the list and
    // the detail screen the ring has no Material ancestor, and Flutter would
    // draw its text with yellow "missing style" underlines.
    return Material(
      type: MaterialType.transparency,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _RingPainter(
            progress: snap.progress,
            ringColor: Color(countdown.ringColor),
            trackColor: Color(countdown.trackColor),
            backgroundColor: Color(countdown.backgroundColor),
            clockwise: countdown.clockwise,
            shadow: countdown.dropShadow,
          ),
          child: Center(
            child: SizedBox(
              width: inner,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: size * .3,
                    child: FittedBox(
                      child: Text(
                        snap.valueText,
                        style: TextStyle(
                          fontFamily: countdown.font.family,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                          height: 1,
                          letterSpacing: -size * .006,
                          shadows: shadows,
                        ),
                      ),
                    ),
                  ),
                  if (countdown.showLabel)
                    SizedBox(
                      height: size * .12,
                      child: FittedBox(
                        child: Text(
                          snap.label,
                          style: TextStyle(
                            fontFamily: countdown.font.family,
                            fontWeight: FontWeight.w700,
                            color: textColor,
                            height: 1.1,
                            shadows: shadows,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.ringColor,
    required this.trackColor,
    required this.backgroundColor,
    required this.clockwise,
    required this.shadow,
  });

  static const strokeRatio = .075;

  final double progress;
  final Color ringColor;
  final Color trackColor;
  final Color backgroundColor;
  final bool clockwise;
  final bool shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final center = size.center(Offset.zero);
    final stroke = s * strokeRatio;
    final pad = s * .03;
    final outer = s / 2 - pad;
    final ringRadius = outer - stroke / 2;

    if (shadow) {
      canvas.drawCircle(
        center.translate(0, s * .015),
        outer,
        Paint()
          ..color = Colors.black.withValues(alpha: .5)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * .025),
      );
    }

    canvas.drawCircle(center, outer, Paint()..color = backgroundColor);

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    canvas.drawCircle(center, ringRadius, ringPaint..color = trackColor);

    if (progress > 0) {
      final sweep = 2 * math.pi * progress * (clockwise ? 1 : -1);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: ringRadius),
        -math.pi / 2,
        sweep,
        false,
        ringPaint..color = ringColor,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.ringColor != ringColor ||
      old.trackColor != trackColor ||
      old.backgroundColor != backgroundColor ||
      old.clockwise != clockwise ||
      old.shadow != shadow;
}
