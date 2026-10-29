import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/anime_entities.dart';
import '../../manga_routes.dart';
import '../providers/anime_providers.dart';
import 'manga_widgets.dart';

/// Cover downloaded through the anime source (keeps its headers/cookies).
class AnimeCover extends ConsumerWidget {
  const AnimeCover({super.key, required this.anime, this.radius = 8});

  final Anime anime;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = anime.thumbnailUrl;
    final path = url == null || url.isEmpty
        ? null
        : ref.watch(
            animeCoverFileProvider((sourceId: anime.sourceId, url: url)),
          );

    Widget placeholder([IconData icon = Icons.movie_outlined]) => Container(
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

class AnimeGridCard extends ConsumerWidget {
  const AnimeGridCard({super.key, required this.anime, this.badge});

  final Anime anime;
  final String? badge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inLibrary = ref.watch(
      animeLibraryProvider.select(
        (l) => l.any((e) => e.anime.key == anime.key),
      ),
    );
    final label = badge ?? (inLibrary ? 'In library' : null);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        ref.read(animeCacheProvider.notifier).put(anime);
        context.push(MangaRoutes.animeDetails(anime.key));
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              AnimeCover(anime: anime),
              if (label != null)
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
                      label,
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
            anime.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, height: 1.2),
          ),
        ],
      ),
    );
  }
}
