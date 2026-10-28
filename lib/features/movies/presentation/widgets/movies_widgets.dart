import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/stremio_entities.dart';
import '../../movies_routes.dart';
import '../providers/movies_providers.dart';

/// Network image with a neutral placeholder and no error noise.
class NetImage extends StatelessWidget {
  const NetImage(this.url, {super.key, this.fit = BoxFit.cover, this.icon});

  final String? url;
  final BoxFit fit;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: const Color(0xFF1E1E26),
      child: Center(
        child: Icon(icon ?? Icons.movie_outlined, color: Colors.white24),
      ),
    );
    if (url == null || url!.isEmpty) return placeholder;
    return Image.network(
      url!,
      fit: fit,
      errorBuilder: (_, _, _) => placeholder,
      frameBuilder: (_, child, frame, sync) =>
          sync || frame != null ? child : placeholder,
    );
  }
}

/// Poster with title and year below; opens the title.
class PosterCard extends StatelessWidget {
  const PosterCard({super.key, required this.meta, this.width = 120});

  final MetaPreview meta;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => context.push(MoviesRoutes.title(meta.type, meta.id)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NetImage(meta.poster),
                    if (meta.imdbRating?.isNotEmpty ?? false)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: _RatingChip(meta.imdbRating!),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              meta.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            if (meta.releaseInfo != null)
              Text(
                meta.releaseInfo!,
                style: const TextStyle(fontSize: 11.5, color: Colors.white54),
              ),
          ],
        ),
      ),
    );
  }
}

class _RatingChip extends StatelessWidget {
  const _RatingChip(this.rating);

  final String rating;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star, size: 11, color: Color(0xFFF5C518)),
        const SizedBox(width: 2),
        Text(rating, style: const TextStyle(fontSize: 10.5)),
      ],
    ),
  );
}

/// Section title with an optional "See all".
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.onMore});

  final String title;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 18, 8, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ),
        if (onMore != null)
          TextButton(onPressed: onMore, child: const Text('See all')),
      ],
    ),
  );
}

/// Thin progress line for partly watched items.
class WatchProgressBar extends StatelessWidget {
  const WatchProgressBar(this.fraction, {super.key});

  final double fraction;

  @override
  Widget build(BuildContext context) => LinearProgressIndicator(
    value: fraction,
    minHeight: 3,
    color: moviesAccent,
    backgroundColor: Colors.white24,
  );
}

class MessageView extends StatelessWidget {
  const MessageView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: Colors.white30),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    ),
  );
}

String formatBytes(num bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 || i == 0 ? 0 : 1)} ${units[i]}';
}
