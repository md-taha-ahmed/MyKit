import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../../core/i18n/i18n.dart';
import '../providers/fitness_providers.dart';

typedef ChartPoint = ({DateTime x, double y});

/// Minimal line chart for progress over time, with an optional goal line.
class ProgressLineChart extends StatelessWidget {
  const ProgressLineChart({
    super.key,
    required this.points,
    this.goal,
    this.unit = '',
    this.height = 180,
  });

  final List<ChartPoint> points;
  final double? goal;
  final String unit;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            tr('No entries yet'),
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _ChartPainter(points: points, goal: goal, unit: unit),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({required this.points, this.goal, required this.unit});

  final List<ChartPoint> points;
  final double? goal;
  final String unit;

  static const _left = 38.0;
  static const _bottom = 20.0;
  static const _top = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    final values = [for (final p in points) p.y, ?goal];
    var lo = values.reduce(math.min);
    var hi = values.reduce(math.max);
    if (hi - lo < 2) {
      lo -= 1;
      hi += 1;
    }
    final pad = (hi - lo) * 0.1;
    lo -= pad;
    hi += pad;

    final t0 = points.first.x.millisecondsSinceEpoch.toDouble();
    var t1 = points.last.x.millisecondsSinceEpoch.toDouble();
    if (t1 - t0 < 1) t1 = t0 + 86400000;

    final w = size.width - _left - 8;
    final h = size.height - _bottom - _top;
    Offset at(DateTime x, double y) => Offset(
      _left + (x.millisecondsSinceEpoch - t0) / (t1 - t0) * w,
      _top + (1 - (y - lo) / (hi - lo)) * h,
    );

    final grid = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1;
    final label = TextStyle(color: Colors.white54, fontSize: 10.5);
    for (var i = 0; i <= 3; i++) {
      final v = lo + (hi - lo) * i / 3;
      final y = _top + (1 - i / 3) * h;
      canvas.drawLine(Offset(_left, y), Offset(size.width - 8, y), grid);
      _text(canvas, v.toStringAsFixed(0), Offset(0, y - 7), label);
    }

    final fmt = DateFormat('d MMM');
    _text(
      canvas,
      fmt.format(points.first.x),
      Offset(_left, size.height - 14),
      label,
    );
    if (points.length > 1) {
      final end = fmt.format(points.last.x);
      _text(canvas, end, Offset(size.width - 44, size.height - 14), label);
    }

    if (goal != null) {
      final y = at(points.first.x, goal!).dy;
      final dash = Paint()
        ..color = Colors.amber.withValues(alpha: 0.7)
        ..strokeWidth = 1.2;
      for (var x = _left; x < size.width - 8; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(x + 4, y), dash);
      }
      _text(
        canvas,
        tr('Goal {0}{unit}', {'0': goal!.toStringAsFixed(0), 'unit': unit}),
        Offset(size.width - 80, y - 14),
        const TextStyle(color: Colors.amber, fontSize: 10.5),
      );
    }

    final path = Path();
    for (final (i, p) in points.indexed) {
      final o = at(p.x, p.y);
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = fitnessAccent
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
    final dot = Paint()..color = fitnessAccent;
    for (final p in points) {
      canvas.drawCircle(at(p.x, p.y), points.length > 40 ? 1.5 : 3, dot);
    }
  }

  void _text(Canvas c, String s, Offset o, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, o);
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.points != points || old.goal != goal;
}
