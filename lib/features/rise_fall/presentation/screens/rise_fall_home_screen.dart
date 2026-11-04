import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/story_models.dart';
import '../../rise_fall_routes.dart';
import '../providers/rise_fall_providers.dart';

class RiseFallHomeScreen extends ConsumerWidget {
  const RiseFallHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stories = ref.watch(storiesProvider);
    final progress = ref.watch(storyProgressProvider);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('سقوط ونهوض')),
        body: stories.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('تعذّر فتح القصص: $e')),
          data: (all) {
            final last = all
                .where((c) => c.id == progress.lastCountry)
                .firstOrNull;
            final lastPart = progress.lastPart;
            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text(
                    'ليست ملخصات. كل دولة قصة طويلة: كيف سقطت، وما مشكلتها الحقيقية، وما جرّبته ففشل، وكيف خرجت ببطء، وما بقي مكسوراً.',
                    style: TextStyle(color: Colors.white70, height: 1.6),
                  ),
                ),
                if (last != null &&
                    lastPart != null &&
                    lastPart < last.parts.length)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: const Icon(Icons.play_arrow_rounded),
                      title: Text('تابع: ${last.name}'),
                      subtitle: Text(last.parts[lastPart].title),
                      onTap: () =>
                          context.push(RiseFallRoutes.part(last.id, lastPart)),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.push(RiseFallRoutes.patterns),
                        icon: const Icon(Icons.hub_outlined),
                        label: const Text('الأنماط'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.push(RiseFallRoutes.compare),
                        icon: const Icon(Icons.compare_arrows),
                        label: const Text('قارن دولتين'),
                      ),
                    ),
                  ],
                ),
                for (final group in StoryGroup.values) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
                    child: Text(
                      group.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  for (final c in all.where((c) => c.group == group))
                    _CountryCard(country: c, read: progress.readIn(c.id)),
                ],
                const SizedBox(height: 16),
                const Text(
                  'هذه القصص كتبها الذكاء الاصطناعي Claude من معرفته بالتاريخ، وليست كتاب مؤرخ، وقد تحتوي أخطاء. تجد في نهاية كل دولة كتباً ومراجع للتحقق.',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 12.5,
                    height: 1.5,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CountryCard extends StatelessWidget {
  const _CountryCard({required this.country, required this.read});

  final StoryCountry country;
  final int read;

  @override
  Widget build(BuildContext context) {
    final total = country.parts.length;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(RiseFallRoutes.country(country.id)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      country.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '$total أجزاء · ${country.minutes} د',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                country.tagline,
                style: const TextStyle(color: Colors.white70, height: 1.5),
              ),
              const SizedBox(height: 10),
              // The arc at a glance: red falls, green rises.
              Row(
                children: [
                  for (final p in country.parts)
                    Expanded(
                      child: Container(
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color: moodColors[p.mood]!.withValues(
                            alpha: p.index < read || read == total ? 1 : 0.45,
                          ),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                ],
              ),
              if (read > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'قرأت $read من $total',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
