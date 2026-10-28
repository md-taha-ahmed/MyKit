import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/entities/feed_article.dart';
import '../providers/rss_providers.dart';

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

  FeedArticle? _find(List<FeedArticle> articles) {
    for (final a in articles) {
      if (a.id == widget.articleId) return a;
    }
    return null;
  }

  Future<void> _open(String link) async {
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
    final article = _find(ref.watch(rssArticlesProvider).articles);
    if (article == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Article not found.')),
      );
    }

    final feed = ref.watch(rssLibraryProvider).feedById(article.feedId);
    final isRead = ref.watch(rssReadIdsProvider).contains(article.id);
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
            tooltip: isRead ? 'Mark as unread' : 'Mark as read',
            icon: Icon(isRead ? Icons.mark_email_unread_outlined : Icons.done),
            onPressed: () {
              final notifier = ref.read(rssReadIdsProvider.notifier);
              isRead
                  ? notifier.markUnread(article.id)
                  : notifier.markRead([article.id]);
            },
          ),
          if (link != null)
            IconButton(
              tooltip: 'Open in browser',
              icon: const Icon(Icons.open_in_new),
              onPressed: () => _open(link),
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
              onPressed: () => _open(link),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Read full article'),
            ),
          ],
        ],
      ),
    );
  }
}
