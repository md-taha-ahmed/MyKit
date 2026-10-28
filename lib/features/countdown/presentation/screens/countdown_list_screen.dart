import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../countdown_routes.dart';
import '../../domain/entities/countdown.dart';
import '../../domain/services/countdown_calculator.dart';
import '../providers/countdown_providers.dart';
import '../widgets/countdown_ring.dart';

class CountdownListScreen extends ConsumerWidget {
  const CountdownListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countdowns = [...ref.watch(countdownsProvider)]
      ..sort(
        (a, b) => CountdownCalculator.snapshot(a).daysRemaining.compareTo(
          CountdownCalculator.snapshot(b).daysRemaining,
        ),
      );

    return Scaffold(
      appBar: AppBar(title: const Text('Countdowns')),
      body: countdowns.isEmpty
          ? const _EmptyState()
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: .8,
              ),
              itemCount: countdowns.length,
              itemBuilder: (context, i) => _CountdownTile(countdowns[i]),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(CountdownRoutes.create),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _CountdownTile extends StatelessWidget {
  const _CountdownTile(this.countdown);

  final Countdown countdown;

  @override
  Widget build(BuildContext context) {
    final title = countdown.title.trim();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(CountdownRoutes.detail(countdown.id)),
        onLongPress: () => context.push(CountdownRoutes.edit(countdown.id)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) => Hero(
                    tag: 'countdown-${countdown.id}',
                    child: CountdownRing(
                      countdown: countdown,
                      size: c.biggest.shortestSide,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                title.isEmpty ? 'Untitled' : title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  color: title.isEmpty ? Colors.white54 : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.timelapse, size: 72, color: Colors.white24),
            const SizedBox(height: 16),
            Text(
              'No countdowns yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap + to create one, then add it to your home screen '
              'as a widget.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }
}
