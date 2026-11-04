import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/utils/text_direction.dart';

import '../../domain/entities/rss_feed.dart';
import '../../rss_routes.dart';
import '../providers/rss_providers.dart';
import 'add_feed_sheet.dart';

const youtubeRed = Color(0xFFFF3B30);

/// Human title for what's selected on the home screen.
String rssFilterTitle(WidgetRef ref, ArticleFilter filter) {
  final library = ref.watch(rssLibraryProvider);
  if (filter.feedId != null) {
    return library.feedById(filter.feedId!)?.title ?? tr('Feed');
  }
  return switch (filter.categoryId) {
    null => tr('All feeds'),
    savedArticlesFilter => tr('Saved'),
    likedArticlesFilter => tr('Liked'),
    final id => library.categoryById(id)?.name ?? tr('All feeds'),
  };
}

/// Side drawer: All / Saved / Liked, then foldable categories with feeds.
class FeedsDrawer extends ConsumerWidget {
  const FeedsDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(rssLibraryProvider);
    final reactions = ref.watch(rssReactionsProvider);
    final selected = ref.watch(selectedRssFilterProvider);
    final collapsed = ref.watch(collapsedRssCategoriesProvider);

    void select(ArticleFilter f) {
      ref.read(selectedRssFilterProvider.notifier).select(f);
      Navigator.of(context).pop();
    }

    int unread(ArticleFilter f) => ref.watch(unreadCountProvider(f));

    // Folders inside [parentId], each followed (when open) by its sub-folders
    // and then its own feeds.
    List<Widget> branch(String? parentId, int depth) => [
      for (final c in library.childrenOf(parentId)) ...[
        _CategoryRow(
          name: c.name,
          depth: depth,
          feedCount: library.feedsUnder(c.id).length,
          hasContent:
              library.childrenOf(c.id).isNotEmpty ||
              library.feedsIn(c.id).isNotEmpty,
          unread: unread((categoryId: c.id, feedId: null)),
          expanded: !collapsed.contains(c.id),
          selected: selected.categoryId == c.id && selected.feedId == null,
          onToggle: () =>
              ref.read(collapsedRssCategoriesProvider.notifier).toggle(c.id),
          onTap: () => select((categoryId: c.id, feedId: null)),
        ),
        if (!collapsed.contains(c.id)) ...[
          ...branch(c.id, depth + 1),
          for (final f
              in library.feedsIn(c.id)..sort(
                (a, b) =>
                    a.title.toLowerCase().compareTo(b.title.toLowerCase()),
              ))
            _FeedRow(
              feed: f,
              depth: depth + 1,
              unread: unread((categoryId: null, feedId: f.id)),
              selected: selected.feedId == f.id,
              onTap: () => select((categoryId: null, feedId: f.id)),
            ),
        ],
      ],
    ];

    return Drawer(
      backgroundColor: const Color(0xFF1B1B1D),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.rss_feed, color: Color(0xFFFF8A3D)),
                  SizedBox(width: 12),
                  Text(
                    tr('Feeds'),
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  _Row(
                    icon: Icons.all_inbox,
                    label: tr('All feeds'),
                    count: unread(allArticles),
                    selected: selected == allArticles,
                    onTap: () => select(allArticles),
                  ),
                  _Row(
                    icon: Icons.bookmark,
                    label: tr('Saved'),
                    count: reactions.saved.length,
                    countIsTotal: true,
                    selected: selected.categoryId == savedArticlesFilter,
                    onTap: () =>
                        select((categoryId: savedArticlesFilter, feedId: null)),
                  ),
                  _Row(
                    icon: Icons.favorite,
                    label: tr('Liked'),
                    count: reactions.liked.length,
                    countIsTotal: true,
                    selected: selected.categoryId == likedArticlesFilter,
                    onTap: () =>
                        select((categoryId: likedArticlesFilter, feedId: null)),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(20, 16, 20, 6),
                    child: Text(
                      tr('CATEGORIES'),
                      style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 1,
                        color: Colors.white38,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  ...branch(null, 0),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: const Icon(Icons.add),
              title: Text(tr('Add feed')),
              onTap: () {
                Navigator.of(context).pop();
                showAddFeedSheet(context);
              },
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.subscriptions, color: youtubeRed),
              title: Text(tr('Import YouTube subscriptions')),
              onTap: () {
                final router = GoRouter.of(context);
                Navigator.of(context).pop();
                router.push(RssRoutes.youtubeImport);
              },
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.folder_open),
              title: Text(tr('Manage feeds & categories')),
              onTap: () {
                final router = GoRouter.of(context);
                Navigator.of(context).pop();
                router.push(RssRoutes.manage);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.countIsTotal = false,
  });

  final IconData icon;
  final String label;
  final int count;
  final bool selected;
  final bool countIsTotal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return _Selectable(
      selected: selected,
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 22, color: selected ? accent : Colors.white70),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          _Count(count, muted: countIsTotal),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.name,
    required this.depth,
    required this.hasContent,
    required this.feedCount,
    required this.unread,
    required this.expanded,
    required this.selected,
    required this.onToggle,
    required this.onTap,
  });

  final String name;

  /// 0 for top-level folders; sub-folders are indented.
  final int depth;

  /// Has sub-folders or feeds of its own (so it can fold).
  final bool hasContent;

  /// Feeds in this folder and all its sub-folders.
  final int feedCount;
  final int unread;
  final bool expanded;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Selectable(
      selected: selected,
      onTap: onTap,
      leftPadding: 8.0 + depth * 18,
      child: Row(
        children: [
          // The chevron folds; the rest of the row opens the category.
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: hasContent ? onToggle : null,
            icon: AnimatedRotation(
              turns: expanded ? .25 : 0,
              duration: const Duration(milliseconds: 150),
              child: const Icon(Icons.chevron_right, size: 22),
            ),
          ),
          const Icon(Icons.folder_outlined, size: 20, color: Colors.white70),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
          if (feedCount == 0)
            const Text(
              'empty',
              style: TextStyle(color: Colors.white30, fontSize: 12),
            )
          else
            _Count(unread),
        ],
      ),
    );
  }
}

class _FeedRow extends StatelessWidget {
  const _FeedRow({
    required this.feed,
    required this.depth,
    required this.unread,
    required this.selected,
    required this.onTap,
  });

  final RssFeed feed;

  /// Depth of the folder it's in, plus one.
  final int depth;
  final int unread;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Selectable(
      selected: selected,
      onTap: onTap,
      leftPadding: 56.0 + (depth - 1) * 18,
      child: Row(
        children: [
          feed.isYoutube
              ? const Icon(Icons.play_circle_fill, size: 18, color: youtubeRed)
              : CircleAvatar(
                  radius: 9,
                  backgroundColor: Colors.white10,
                  child: Text(
                    feed.title.isEmpty ? '?' : feed.title[0].toUpperCase(),
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              feed.title,
              textDirection: textDirectionOf(feed.title),
              textAlign: TextAlign.left,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                color: unread > 0 ? Colors.white : Colors.white54,
                fontWeight: selected ? FontWeight.w700 : null,
              ),
            ),
          ),
          _Count(unread),
        ],
      ),
    );
  }
}

class _Selectable extends StatelessWidget {
  const _Selectable({
    required this.selected,
    required this.onTap,
    required this.child,
    this.leftPadding = 20,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final double leftPadding;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: selected ? accent.withValues(alpha: .16) : Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(leftPadding - 8, 10, 16, 10),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.n, {this.muted = false});

  final int n;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    if (n == 0) return const SizedBox.shrink();
    return Text(
      '$n',
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: muted ? Colors.white38 : Theme.of(context).colorScheme.primary,
      ),
    );
  }
}
