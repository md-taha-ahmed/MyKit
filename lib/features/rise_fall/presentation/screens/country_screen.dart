import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/story_models.dart';
import '../../rise_fall_routes.dart';
import '../providers/rise_fall_providers.dart';

/// A country's story as a timeline of falls and rises.
class CountryScreen extends ConsumerWidget {
  const CountryScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final country = ref.watch(storyCountryProvider(id));
    final progress = ref.watch(storyProgressProvider);
    if (country == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(country.name)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
              child: Text(
                country.tagline,
                style: const TextStyle(color: Colors.white70, height: 1.6),
              ),
            ),
            for (final p in country.parts)
              _PartRow(
                part: p,
                isRead: progress.isRead(id, p.index),
                onTap: () => context.push(RiseFallRoutes.part(id, p.index)),
              ),
            const SizedBox(height: 14),
            const Text(
              'مراجع للتحقق والاستزادة',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              country.note ??
                  'كُتبت القصة من معرفة Claude العامة بالتاريخ. هذه مراجع موثوقة لمن يريد التحقق أو التعمق، وليست توثيقاً لكل جملة.',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
            for (final s in country.sources)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  s.url == null ? Icons.menu_book_outlined : Icons.link,
                  size: 18,
                ),
                title: Directionality(
                  textDirection: _startsArabic(s.title)
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  child: Text(s.title, textAlign: TextAlign.start),
                ),
                onTap: s.url == null
                    ? null
                    : () => launchUrl(
                        Uri.parse(s.url!),
                        mode: LaunchMode.externalApplication,
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

bool _startsArabic(String text) =>
    RegExp(r'^[\u0600-\u06FF]').hasMatch(text.trimLeft());

/// One part on the country's timeline. The line is drawn behind the row, so
/// the card's height comes from its text alone.
class _PartRow extends StatelessWidget {
  const _PartRow({
    required this.part,
    required this.isRead,
    required this.onTap,
  });

  final StoryPart part;
  final bool isRead;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      PositionedDirectional(
        start: 6,
        top: 16,
        bottom: 0,
        child: Container(width: 2, color: Colors.white24),
      ),
      PositionedDirectional(
        start: 0,
        top: 16,
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: moodColors[part.mood],
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsetsDirectional.only(start: 24, bottom: 8),
        child: Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          part.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${part.period} · ${part.mood.label}',
                          style: const TextStyle(color: Colors.white54),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          part.oneLine,
                          style: const TextStyle(
                            color: Colors.white70,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isRead) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.check_circle, color: Colors.white54),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
