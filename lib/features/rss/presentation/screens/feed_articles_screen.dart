import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/rss_providers.dart';
import '../widgets/article_list.dart';

/// Articles of a single feed.
class FeedArticlesScreen extends ConsumerWidget {
  const FeedArticlesScreen({super.key, required this.feedId});

  final String feedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(rssLibraryProvider).feedById(feedId);
    if (feed == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This feed was removed.')),
      );
    }
    final filter = (categoryId: null, feedId: feedId);
    final site = feed.siteUrl;

    return Scaffold(
      appBar: AppBar(
        title: Text(feed.title),
        actions: [
          if (site != null)
            IconButton(
              tooltip: 'Open website',
              icon: const Icon(Icons.public),
              onPressed: () => launchUrl(
                Uri.parse(site),
                mode: LaunchMode.externalApplication,
              ),
            ),
          IconButton(
            tooltip: 'Mark all as read',
            icon: const Icon(Icons.done_all),
            onPressed: () {
              final ids = ref
                  .read(filteredArticlesProvider(filter))
                  .map((a) => a.id);
              ref.read(rssReadIdsProvider.notifier).markRead(ids);
            },
          ),
          IconButton(
            tooltip: 'Mark all as unread',
            icon: const Icon(Icons.mark_email_unread_outlined),
            onPressed: () {
              final ids = ref
                  .read(filteredArticlesProvider(filter))
                  .map((a) => a.id);
              ref.read(rssReadIdsProvider.notifier).markAllUnread(ids);
            },
          ),
        ],
      ),
      body: ArticleList(
        filter: filter,
        empty: RssEmptyState(
          icon: Icons.inbox_outlined,
          title: 'No articles',
          message:
              ref.watch(rssArticlesProvider).errors[feedId] ??
              'Pull down to refresh.',
        ),
      ),
    );
  }
}
