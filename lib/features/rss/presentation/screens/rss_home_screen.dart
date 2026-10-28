import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../rss_routes.dart';
import '../providers/rss_providers.dart';
import '../widgets/add_feed_sheet.dart';
import '../widgets/article_list.dart';
import '../widgets/feeds_drawer.dart';

/// Articles from the selection in the feeds drawer (all, a category, a feed,
/// Saved or Liked).
class RssHomeScreen extends ConsumerStatefulWidget {
  const RssHomeScreen({super.key});

  @override
  ConsumerState<RssHomeScreen> createState() => _RssHomeScreenState();
}

class _RssHomeScreenState extends ConsumerState<RssHomeScreen> {
  static const _staleAfter = Duration(minutes: 15);
  final _scaffold = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    // Refresh when opened, unless we just did.
    Future.microtask(() {
      final state = ref.read(rssArticlesProvider);
      final last = state.lastRefreshed;
      if (last == null || DateTime.now().difference(last) > _staleAfter) {
        ref.read(rssArticlesProvider.notifier).refresh();
      }
    });
  }

  void _markAllRead(ArticleFilter filter) {
    final ids = ref.read(filteredArticlesProvider(filter)).map((a) => a.id);
    ref.read(rssReadIdsProvider.notifier).markRead(ids);
  }

  void _markAllUnread(ArticleFilter filter) {
    final ids = ref.read(filteredArticlesProvider(filter)).map((a) => a.id);
    ref.read(rssReadIdsProvider.notifier).markAllUnread(ids);
  }

  /// The selection, falling back to All if its category/feed was deleted.
  ArticleFilter _validFilter() {
    final f = ref.watch(selectedRssFilterProvider);
    final library = ref.watch(rssLibraryProvider);
    if (f.feedId != null) {
      return library.feedById(f.feedId!) != null ? f : allArticles;
    }
    final id = f.categoryId;
    if (id == null || id == savedArticlesFilter || id == likedArticlesFilter) {
      return f;
    }
    return library.categoryById(id) != null ? f : allArticles;
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(rssLibraryProvider);
    final articlesState = ref.watch(rssArticlesProvider);
    final filter = _validFilter();
    final unread = ref.watch(unreadCountProvider(filter));
    final failed = articlesState.errors.length;

    return Scaffold(
      key: _scaffold,
      drawer: const FeedsDrawer(),
      appBar: AppBar(
        titleSpacing: 0,
        // Tapping the title opens the feeds drawer.
        title: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _scaffold.currentState?.openDrawer(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        rssFilterTitle(ref, filter),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        unread == 0 ? 'All caught up' : '$unread unread',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        ),
        leading: IconButton(
          tooltip: 'Feeds & categories',
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffold.currentState?.openDrawer(),
        ),
        actions: [
          if (articlesState.refreshing)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.read(rssArticlesProvider.notifier).refresh(),
            ),
          IconButton(
            tooltip: 'Brief view (swipe through articles)',
            icon: const Icon(Icons.view_day_outlined),
            onPressed: () => context.push(
              RssRoutes.scroll(
                categoryId: filter.categoryId,
                feedId: filter.feedId,
              ),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'read') _markAllRead(filter);
              if (v == 'unread') _markAllUnread(filter);
              if (v == 'manage') context.push(RssRoutes.manage);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'read', child: Text('Mark all as read')),
              PopupMenuItem(value: 'unread', child: Text('Mark all as unread')),
              PopupMenuItem(
                value: 'manage',
                child: Text('Manage feeds & categories'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (failed > 0 && !articlesState.refreshing)
            MaterialBanner(
              backgroundColor: const Color(0xFF3A2A1A),
              leading: const Icon(Icons.warning_amber, color: Colors.orange),
              content: Text(
                failed == 1
                    ? '1 feed could not be updated.'
                    : '$failed feeds could not be updated.',
              ),
              actions: [
                TextButton(
                  onPressed: () => context.push(RssRoutes.manage),
                  child: const Text('VIEW'),
                ),
              ],
            ),
          Expanded(
            child: ArticleList(
              filter: filter,
              empty: library.feeds.isEmpty
                  ? RssEmptyState(
                      icon: Icons.rss_feed,
                      title: 'No feeds yet',
                      message:
                          'Add your favourite sites and YouTube channels, '
                          'organised into categories.',
                      action: FilledButton.icon(
                        onPressed: () => showAddFeedSheet(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Add your first feed'),
                      ),
                    )
                  : RssEmptyState(
                      icon: Icons.inbox_outlined,
                      title: articlesState.refreshing
                          ? 'Loading…'
                          : 'Nothing here',
                      message: switch (filter.categoryId) {
                        savedArticlesFilter =>
                          'No bookmarks yet. Swipe an article right to save it.',
                        likedArticlesFilter =>
                          'Nothing liked yet. Double-tap an article in the '
                              'brief view to like it.',
                        _ => 'Pull down to refresh.',
                      },
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton: library.feeds.isEmpty
          ? null
          : FloatingActionButton(
              tooltip: 'Add feed',
              onPressed: () => showAddFeedSheet(
                context,
                initialCategoryId: filter.feedId == null
                    ? filter.categoryId
                    : library.feedById(filter.feedId!)?.categoryId,
              ),
              child: const Icon(Icons.add),
            ),
    );
  }
}
