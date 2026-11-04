import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/i18n/i18n.dart';
import '../../countdown_routes.dart';
import '../../domain/services/countdown_calculator.dart';
import '../providers/countdown_providers.dart';
import '../widgets/countdown_ring.dart';

/// Full-screen view shown when a countdown (or its home widget) is tapped.
class CountdownDetailScreen extends ConsumerWidget {
  const CountdownDetailScreen({super.key, required this.countdownId});

  final String countdownId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countdown = ref.watch(countdownByIdProvider(countdownId));

    void close() =>
        context.canPop() ? context.pop() : context.go(CountdownRoutes.list);

    if (countdown == null) {
      return Scaffold(
        appBar: AppBar(leading: CloseButton(onPressed: close)),
        body: Center(child: Text(tr('This countdown no longer exists.'))),
      );
    }

    final snap = CountdownCalculator.snapshot(countdown);
    final heading = countdown.title.trim().isEmpty
        ? DateFormat('dd/MM/yy').format(snap.effectiveDate)
        : countdown.title;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0C),
      body: SafeArea(
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                iconSize: 32,
                icon: const Icon(Icons.close),
                onPressed: close,
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Hero(
                      tag: 'countdown-${countdown.id}',
                      child: CountdownRing(countdown: countdown, size: 230),
                    ),
                    const SizedBox(height: 56),
                    Text(
                      tr('Countdown for'),
                      style: TextStyle(
                        fontSize: 22,
                        color: Colors.white.withValues(alpha: .8),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      heading,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    if (countdown.title.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          DateFormat(
                            'EEEE, d MMMM y',
                          ).format(snap.effectiveDate),
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    if (countdown.notes.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Text(
                          countdown.notes,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.large(
        onPressed: () => context.push(CountdownRoutes.edit(countdown.id)),
        child: const Icon(Icons.edit, size: 36),
      ),
    );
  }
}
