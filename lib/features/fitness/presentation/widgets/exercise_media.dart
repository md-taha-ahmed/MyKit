import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/fitness_entities.dart';
import '../providers/fitness_providers.dart';

/// The exercise's photos: the user's own first, then the database's start and
/// end positions. They cross-fade smoothly, pausing at each position, so two
/// photos read as one movement.
class ExerciseMedia extends ConsumerStatefulWidget {
  const ExerciseMedia({
    super.key,
    required this.exercise,
    this.height = 220,
    this.animate = true,
    this.radius = 14,
  });

  final Exercise exercise;
  final double height;
  final bool animate;
  final double radius;

  @override
  ConsumerState<ExerciseMedia> createState() => _ExerciseMediaState();
}

class _ExerciseMediaState extends ConsumerState<ExerciseMedia>
    with SingleTickerProviderStateMixin {
  /// One step = hold on a photo, then blend into the next.
  late final AnimationController _step = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..addStatusListener(_onStatus);

  /// Blend amount over a step: hold (35%), ease into the next photo (65%).
  static final _blend = TweenSequence<double>([
    TweenSequenceItem(tween: ConstantTween(0), weight: 35),
    TweenSequenceItem(
      tween: Tween(
        begin: 0.0,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeInOutCubic)),
      weight: 65,
    ),
  ]);

  int _index = 0;
  int _count = 0;

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    setState(() => _index = (_index + 1) % (_count == 0 ? 1 : _count));
    _step.forward(from: 0);
  }

  @override
  void dispose() {
    _step.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final custom = ref.watch(customImagesProvider)[widget.exercise.id] ?? [];
    final db = [
      for (final path in widget.exercise.images)
        ref.watch(exerciseImageFileProvider(path)),
    ];
    // Only photos that are on disk take part, so nothing flickers.
    final files = <File>[
      for (final p in custom) File(p),
      for (final f in db) ?f.value,
    ];
    final loading = db.any((f) => f.isLoading);

    _count = files.length;
    if (_index >= _count) _index = 0;
    final animate = widget.animate && _count > 1;
    if (animate && !_step.isAnimating) {
      _step.forward(from: 0);
    } else if (!animate && _step.isAnimating) {
      _step.stop();
    }

    final Widget child;
    if (files.isEmpty) {
      child = _placeholder(loading: loading);
    } else if (!animate) {
      child = _image(files.first);
    } else {
      final current = files[_index];
      final next = files[(_index + 1) % files.length];
      child = AnimatedBuilder(
        animation: _step,
        builder: (context, _) {
          final t = _blend.transform(_step.value);
          return Stack(
            fit: StackFit.expand,
            children: [
              _image(current),
              Opacity(opacity: t, child: _image(next)),
            ],
          );
        },
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: ColoredBox(color: Colors.white, child: child),
      ),
    );
  }

  Widget _image(File f) => Image.file(
    f,
    key: ValueKey(f.path),
    fit: BoxFit.contain,
    gaplessPlayback: true,
    cacheWidth: widget.height < 120 ? 240 : 900,
    errorBuilder: (_, _, _) => _placeholder(),
  );

  Widget _placeholder({bool loading = false}) => ColoredBox(
    color: const Color(0xFF2A2A30),
    child: Center(
      child: loading
          ? const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.fitness_center, color: Colors.white24, size: 36),
    ),
  );
}

/// Small square thumbnail (first photo, no animation).
class ExerciseThumb extends StatelessWidget {
  const ExerciseThumb({super.key, required this.exercise, this.size = 56});

  final Exercise exercise;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: ExerciseMedia(
      exercise: exercise,
      height: size,
      animate: false,
      radius: 10,
    ),
  );
}
