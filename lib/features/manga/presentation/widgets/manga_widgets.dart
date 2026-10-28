import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/manga_entities.dart';
import '../../domain/repositories/manga_repository.dart';
import '../../manga_routes.dart';
import '../providers/manga_providers.dart';

const mangaAccent = Color(0xFFE5484D);

/// Cover downloaded through the source (keeps its headers/cookies).
class MangaCover extends ConsumerWidget {
  const MangaCover({super.key, required this.manga, this.radius = 8});

  final Manga manga;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = manga.thumbnailUrl;
    final path = url == null || url.isEmpty
        ? null
        : ref.watch(coverFileProvider((sourceId: manga.sourceId, url: url)));

    Widget placeholder([IconData icon = Icons.image_outlined]) => Container(
      color: const Color(0xFF2E2E32),
      alignment: Alignment.center,
      child: Icon(icon, color: Colors.white24),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: AspectRatio(
        aspectRatio: 0.7,
        child: path == null
            ? placeholder()
            : path.when(
                loading: () => placeholder(),
                error: (_, _) => placeholder(Icons.broken_image_outlined),
                data: (p) => Image.file(
                  File(p),
                  fit: BoxFit.cover,
                  cacheWidth: 360,
                  errorBuilder: (_, _, _) =>
                      placeholder(Icons.broken_image_outlined),
                ),
              ),
      ),
    );
  }
}

class MangaGridCard extends ConsumerWidget {
  const MangaGridCard({super.key, required this.manga, this.badge});

  final Manga manga;
  final String? badge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inLibrary = ref.watch(
      mangaLibraryProvider.select(
        (l) => l.any((e) => e.manga.key == manga.key),
      ),
    );
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        ref.read(mangaCacheProvider.notifier).put(manga);
        context.push(MangaRoutes.details(manga.key));
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              MangaCover(manga: manga),
              if (inLibrary || badge != null)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: mangaAccent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      badge ?? 'In library',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            manga.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, height: 1.2),
          ),
        ],
      ),
    );
  }
}

const mangaGridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 140,
  mainAxisSpacing: 12,
  crossAxisSpacing: 10,
  childAspectRatio: .54,
);

/// Error message; long-press shows the extension's stack trace.
class MangaErrorView extends StatelessWidget {
  const MangaErrorView({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final details = error is MangaException
        ? (error as MangaException).details
        : null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.white30),
            const SizedBox(height: 12),
            GestureDetector(
              onLongPress: details == null
                  ? null
                  : () => showDialog<void>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Details'),
                        content: SingleChildScrollView(
                          child: SelectableText(
                            details,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                    ),
              child: Text(
                '$error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}

/// "en" → "English" for the common ones.
String languageName(String code) =>
    const {
      'all': 'Multi',
      'en': 'English',
      'ar': 'Arabic',
      'es': 'Spanish',
      'es-419': 'Spanish (LatAm)',
      'fr': 'French',
      'de': 'German',
      'it': 'Italian',
      'id': 'Indonesian',
      'ja': 'Japanese',
      'ko': 'Korean',
      'pt': 'Portuguese',
      'pt-BR': 'Portuguese (BR)',
      'ru': 'Russian',
      'tr': 'Turkish',
      'vi': 'Vietnamese',
      'th': 'Thai',
      'pl': 'Polish',
      'uk': 'Ukrainian',
      'zh': 'Chinese',
      'zh-Hans': 'Chinese (Simplified)',
      'zh-Hant': 'Chinese (Traditional)',
    }[code] ??
    code;
