import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/fitness_entities.dart';
import '../providers/fitness_providers.dart';

/// The exercise's photos: the user's own first, then the database's start and
/// end positions, alternated like a slow GIF.
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

class _ExerciseMediaState extends ConsumerState<ExerciseMedia> {
  Timer? _timer;
  int _frame = 0;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _timer = Timer.periodic(const Duration(milliseconds: 900), (_) {
        if (mounted) setState(() => _frame++);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final custom = ref.watch(customImagesProvider)[widget.exercise.id] ?? [];
    final frames = <Widget Function()>[
      for (final path in custom) () => _file(File(path)),
      for (final path in widget.exercise.images)
        () => ref
            .watch(exerciseImageFileProvider(path))
            .when(
              loading: () => _placeholder(loading: true),
              error: (_, _) => _placeholder(),
              data: _file,
            ),
    ];

    final child = frames.isEmpty
        ? _placeholder()
        : AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: KeyedSubtree(
              key: ValueKey(_frame % frames.length),
              child: frames[_frame % frames.length](),
            ),
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: ColoredBox(color: Colors.white, child: child),
      ),
    );
  }

  Widget _file(File f) => Image.file(
    f,
    fit: BoxFit.contain,
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
