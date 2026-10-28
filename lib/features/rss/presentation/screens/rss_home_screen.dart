import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../rss_routes.dart';
import '../providers/rss_providers.dart';
import '../widgets/add_feed_sheet.dart';
import '../widgets/article_list.dart';

/// Articles from all feeds, filtered by category chips.
class RssHomeScreen extends ConsumerStatefulWidget {
  const RssHomeScreen({super.key});

  @override
  ConsumerState<RssHomeScreen> createState() => _RssHomeScreenState();
}

class _RssHomeScreenState extends ConsumerState<RssHomeScreen> {
  static const _staleAfter = Duration(minutes: 15);

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

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(rssLibraryProvider);
    final articlesState = ref.watch(rssArticlesProvider);
    final chosen = ref.watch(selectedRssCategoryProvider);
    // Fall back to "All" if the chosen category was deleted.
    final selected = chosen != null && library.categoryById(chosen) != null
        ? chosen
        : null;
    final filter = (categoryId: selected, feedId: null);
    final failed = articlesState.errors.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('RSS Feeds'),
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
            tooltip: 'Manage feeds & categories',
            icon: const Icon(Icons.folder_open),
            onPressed: () => context.push(RssRoutes.manage),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'read') _markAllRead(filter);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'read', child: Text('Mark all as read')),
            ],
          ),
        ],
        bottom: library.feeds.isEmpty
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: _CategoryChips(selected: selected),
              ),
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
                          'Add your favourite sites and organise them into '
                          'categories.',
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
                      message: selected == null
                          ? 'Pull down to refresh.'
                          : 'No articles in this category yet.',
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton: library.feeds.isEmpty
          ? null
          : FloatingActionButton(
              tooltip: 'Add feed',
              onPressed: () =>
                  showAddFeedSheet(context, initialCategoryId: selected),
              child: const Icon(Icons.add),
            ),
    );
  }
}

class _CategoryChips extends ConsumerWidget {
  const _CategoryChips({required this.selected});

  final String? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(rssLibraryProvider);
    final notifier = ref.read(selectedRssCategoryProvider.notifier);

    Widget chip(String? id, String label) {
      final unread = ref.watch(
        unreadCountProvider((categoryId: id, feedId: null)),
      );
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(unread > 0 ? '$label  $unread' : label),
          selected: selected == id,
          showCheckmark: false,
          onSelected: (_) => notifier.select(id),
        ),
      );
    }

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
        children: [
          chip(null, 'All'),
          for (final c in library.categories)
            if (library.feedsIn(c.id).isNotEmpty) chip(c.id, c.name),
        ],
      ),
    );
  }
}
