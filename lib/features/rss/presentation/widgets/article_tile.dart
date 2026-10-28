import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/feed_article.dart';

/// "5m", "3h", "2d", or a short date for older items.
String relativeTime(DateTime? date, {DateTime? now}) {
  if (date == null) return '';
  final diff = (now ?? DateTime.now()).difference(date);
  if (diff.isNegative || diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return DateFormat('d MMM').format(date);
}

class ArticleTile extends StatelessWidget {
  const ArticleTile({
    super.key,
    required this.article,
    required this.feedTitle,
    required this.isRead,
    this.isSaved = false,
    this.isLiked = false,
    required this.onTap,
  });

  final FeedArticle article;
  final String feedTitle;
  final bool isRead;
  final bool isSaved;
  final bool isLiked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final faded = isRead ? .55 : 1.0;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Opacity(
          opacity: faded,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (!isRead)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            feedTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (isLiked)
                          const Padding(
                            padding: EdgeInsets.only(right: 6),
                            child: Icon(
                              Icons.favorite,
                              size: 14,
                              color: Color(0xFFFF5A6E),
                            ),
                          ),
                        if (isSaved)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Icon(
                              Icons.bookmark,
                              size: 14,
                              color: accent,
                            ),
                          ),
                        Text(
                          relativeTime(article.publishedAt),
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      article.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.25,
                        fontWeight: isRead ? FontWeight.w400 : FontWeight.w600,
                      ),
                    ),
                    if (article.summary.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        article.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: Colors.white60,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (article.imageUrl != null) ...[
                const SizedBox(width: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    article.imageUrl!,
                    width: 84,
                    height: 84,
                    fit: BoxFit.cover,
                    cacheWidth: 252,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
