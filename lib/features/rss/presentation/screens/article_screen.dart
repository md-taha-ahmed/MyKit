import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/platform/external_apps.dart';
import '../providers/rss_providers.dart';
import '../widgets/article_actions.dart';
import '../widgets/article_ai.dart';

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
      ).showSnackBar(const SnackBar(content: Text('Could not open link.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final article = ref.watch(articleByIdProvider(widget.articleId));
    if (article == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Article not found.')),
      );
    }

    final feed = ref.watch(rssLibraryProvider).feedById(article.feedId);
    final isRead = ref.watch(rssReadIdsProvider).contains(article.id);
    final reactions = ref.watch(rssReactionsProvider);
    final liked = reactions.isLiked(article.id);
    final saved = reactions.isSaved(article.id);
    final body = article.content.isNotEmpty ? article.content : article.summary;
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
            tooltip: liked ? 'Unlike' : 'Like',
            icon: Icon(
              liked ? Icons.favorite : Icons.favorite_border,
              color: liked ? const Color(0xFFFF5A6E) : null,
            ),
            onPressed: () =>
                ref.read(rssReactionsProvider.notifier).toggleLike(article.id),
          ),
          IconButton(
            tooltip: saved ? 'Remove bookmark' : 'Bookmark',
            icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
            onPressed: () => toggleSaveArticle(context, ref, article),
          ),
          if (link != null)
            IconButton(
              tooltip: 'Open in browser',
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
                child: Text(isRead ? 'Mark as unread' : 'Mark as read'),
              ),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
              const PopupMenuItem(
                value: 'aiKey',
                child: Text('Gemini API key…'),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
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
          Text(
            meta,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 14),
          ArticleAiPanel(articleId: article.id),
          if (article.imageUrl != null) ...[
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                article.imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ],
          const SizedBox(height: 18),
          if (body.isEmpty)
            const Text(
              'This feed only provides a headline. Open the article to read it.',
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
                feed?.isYoutube ?? false ? Icons.play_arrow : Icons.open_in_new,
              ),
              label: Text(
                feed?.isYoutube ?? false
                    ? 'Watch on YouTube'
                    : 'Read full article',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
