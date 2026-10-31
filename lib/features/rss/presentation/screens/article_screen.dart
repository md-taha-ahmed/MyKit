import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/platform/external_apps.dart';
import '../../../../core/utils/text_direction.dart';
import '../../domain/services/reading_time.dart';
import '../providers/offline_providers.dart';
import '../providers/rss_providers.dart';
import '../widgets/article_actions.dart';
import '../widgets/article_ai.dart';
import '../widgets/feed_image.dart';
import '../widgets/reading_time_badge.dart';

/// In-app reading view with a link to the original article.
class ArticleScreen extends ConsumerStatefulWidget {
  const ArticleScreen({super.key, required this.articleId});

  final String articleId;

  @override
  ConsumerState<ArticleScreen> createState() => _ArticleScreenState();
}

class _ArticleScreenState extends ConsumerState<ArticleScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(rssReadIdsProvider.notifier).markRead([widget.articleId]),
    );
  }

  Future<void> _open(String link) async {
    // YouTube links go to ReVanced/YouTube explicitly (Android won't).
    final host = Uri.tryParse(link)?.host ?? '';
    if (host.endsWith('youtube.com') || host == 'youtu.be') {
      await ExternalApps.openYoutube(link);
      return;
    }
    final ok = await launchUrl(
      Uri.parse(link),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr('Could not open link.'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final article = ref.watch(articleByIdProvider(widget.articleId));
    if (article == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(tr('Article not found.'))),
      );
    }

    final feed = ref.watch(rssLibraryProvider).feedById(article.feedId);
    final isRead = ref.watch(rssReadIdsProvider).contains(article.id);
    final reactions = ref.watch(rssReactionsProvider);
    final liked = reactions.isLiked(article.id);
    final saved = reactions.isSaved(article.id);
    final feedText = article.content.isNotEmpty
        ? article.content
        : article.summary;
    // The full text saved for offline reading, when it has more.
    final offlineText = ref.watch(offlineTextProvider(article.id)).value;
    final body = offlineText != null && offlineText.length > feedText.length
        ? offlineText
        : feedText;
    final link = article.link;
    final text = Theme.of(context).textTheme;

    final meta = [
      if (feed != null) feed.title,
      if (article.author != null) article.author!,
      if (article.publishedAt != null)
        DateFormat('d MMM y, HH:mm').format(article.publishedAt!),
    ].join(' · ');

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: liked ? tr('Unlike') : tr('Like'),
            icon: Icon(
              liked ? Icons.favorite : Icons.favorite_border,
              color: liked ? const Color(0xFFFF5A6E) : null,
            ),
            onPressed: () =>
                ref.read(rssReactionsProvider.notifier).toggleLike(article.id),
          ),
          IconButton(
            tooltip: saved ? tr('Remove bookmark') : tr('Bookmark'),
            icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
            onPressed: () => toggleSaveArticle(context, ref, article),
          ),
          if (link != null)
            IconButton(
              tooltip: tr('Open in browser'),
              icon: const Icon(Icons.open_in_new),
              onPressed: () => _open(link),
            ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'aiKey') {
                await showGeminiKeyDialog(context, ref);
              } else if (v == 'read') {
                final notifier = ref.read(rssReadIdsProvider.notifier);
                isRead
                    ? notifier.markUnread(article.id)
                    : notifier.markRead([article.id]);
              } else if (v == 'delete') {
                final delete = deleteArticle(
                  context,
                  ref,
                  article,
                  fromSaved: false,
                );
                Navigator.of(context).pop();
                await delete;
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'read',
                child: Text(isRead ? tr('Mark as unread') : tr('Mark as read')),
              ),
              PopupMenuItem(value: 'delete', child: Text(tr('Delete'))),
              PopupMenuItem(value: 'aiKey', child: Text(tr('Gemini API key…'))),
            ],
          ),
        ],
      ),
      body: AutoDirection(
        text: '${article.title} $body',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
          children: [
            Text(
              article.title,
              style: text.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  meta,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 13.5,
                  ),
                ),
                if (!(feed?.isYoutube ?? false))
                  ReadingTimeBadge(
                    ReadingTime.of(article, fullText: offlineText),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            ArticleAiPanel(articleId: article.id),
            if (article.imageUrl != null) ...[
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: FeedImage(
                  article.imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ],
            const SizedBox(height: 18),
            if (body.isEmpty)
              Text(
                tr(
                  'This feed only provides a headline. Open the article to read it.',
                ),
                style: TextStyle(color: Colors.white60),
              )
            else
              SelectableText(
                body,
                style: const TextStyle(fontSize: 16.5, height: 1.55),
              ),
            if (link != null) ...[
              const SizedBox(height: 28),
              FilledButton.icon(
                style: feed?.isYoutube ?? false
                    ? FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFF3B30),
                      )
                    : null,
                onPressed: () => _open(link),
                icon: Icon(
                  feed?.isYoutube ?? false
                      ? Icons.play_arrow
                      : Icons.open_in_new,
                ),
                label: Text(
                  feed?.isYoutube ?? false
                      ? tr('Watch on YouTube')
                      : tr('Read full article'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
