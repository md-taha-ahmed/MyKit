import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/dialogs.dart';
import '../../domain/entities/feed_category.dart';
import '../../domain/entities/rss_feed.dart';
import '../../rss_routes.dart';
import '../providers/rss_providers.dart';
import '../widgets/add_feed_sheet.dart';

/// Categories and their feeds: add, rename, move and delete.
class ManageFeedsScreen extends ConsumerWidget {
  const ManageFeedsScreen({super.key});

  Future<void> _addCategory(BuildContext context, WidgetRef ref) async {
    final name = await showTextInputDialog(
      context,
      title: 'New category',
      hint: 'e.g. Tech, News, Design',
      confirmLabel: 'Create',
    );
    if (name != null) {
      await ref.read(rssLibraryProvider.notifier).addCategory(name);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(rssLibraryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Feeds & categories'),
        actions: [
          IconButton(
            tooltip: 'New category',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: () => _addCategory(context, ref),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          for (final category in library.categories)
            _CategorySection(category: category),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        // The app theme makes FABs circular; extended ones need a pill.
        shape: const StadiumBorder(),
        onPressed: () => showAddFeedSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Add feed'),
      ),
    );
  }
}

enum _CategoryAction { addFeed, rename, delete }

class _CategorySection extends ConsumerWidget {
  const _CategorySection({required this.category});

  final FeedCategory category;

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    _CategoryAction action,
  ) async {
    final notifier = ref.read(rssLibraryProvider.notifier);
    switch (action) {
      case _CategoryAction.addFeed:
        await showAddFeedSheet(context, initialCategoryId: category.id);
      case _CategoryAction.rename:
        final name = await showTextInputDialog(
          context,
          title: 'Rename category',
          initialValue: category.name,
        );
        if (name != null) await notifier.renameCategory(category.id, name);
      case _CategoryAction.delete:
        final count = ref.read(rssLibraryProvider).feedsIn(category.id).length;
        final ok = await showConfirmDialog(
          context,
          title: 'Delete "${category.name}"?',
          message: count == 0
              ? 'This category is empty.'
              : 'Its $count ${count == 1 ? 'feed' : 'feeds'} will be '
                    'unsubscribed too. Move feeds to another category first '
                    'to keep them.',
        );
        if (ok) await notifier.deleteCategory(category.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feeds = ref.watch(rssLibraryProvider).feedsIn(category.id);
    final unread = ref.watch(
      unreadCountProvider((categoryId: category.id, feedId: null)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 4, 4),
          child: Row(
            children: [
              Icon(
                Icons.folder,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  category.name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${feeds.length} ${feeds.length == 1 ? 'feed' : 'feeds'}'
                '${unread > 0 ? ' · $unread unread' : ''}',
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              PopupMenuButton<_CategoryAction>(
                onSelected: (a) => _onAction(context, ref, a),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: _CategoryAction.addFeed,
                    child: Text('Add feed here'),
                  ),
                  PopupMenuItem(
                    value: _CategoryAction.rename,
                    child: Text('Rename'),
                  ),
                  PopupMenuItem(
                    value: _CategoryAction.delete,
                    child: Text('Delete'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (feeds.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(46, 0, 16, 8),
            child: Text(
              'No feeds yet',
              style: TextStyle(color: Colors.white38),
            ),
          ),
        for (final feed in feeds) _FeedTile(feed: feed),
        const Divider(height: 16),
      ],
    );
  }
}

enum _FeedAction { rename, move, delete }

class _FeedTile extends ConsumerWidget {
  const _FeedTile({required this.feed});

  final RssFeed feed;

  Future<void> _move(BuildContext context, WidgetRef ref) async {
    final categories = ref.read(rssLibraryProvider).categories;
    final target = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Move to'),
        children: [
          for (final c in categories)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, c.id),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    c.id == feed.categoryId
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(c.name, style: const TextStyle(fontSize: 16)),
                ],
              ),
            ),
        ],
      ),
    );
    if (target != null && target != feed.categoryId) {
      await ref
          .read(rssLibraryProvider.notifier)
          .updateFeed(feed.copyWith(categoryId: target));
    }
  }

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    _FeedAction action,
  ) async {
    final notifier = ref.read(rssLibraryProvider.notifier);
    switch (action) {
      case _FeedAction.rename:
        final name = await showTextInputDialog(
          context,
          title: 'Rename feed',
          initialValue: feed.title,
        );
        if (name != null) await notifier.updateFeed(feed.copyWith(title: name));
      case _FeedAction.move:
        await _move(context, ref);
      case _FeedAction.delete:
        final ok = await showConfirmDialog(
          context,
          title: 'Unsubscribe?',
          message: 'Remove "${feed.title}" and its saved articles.',
          confirmLabel: 'Unsubscribe',
        );
        if (ok) await notifier.deleteFeed(feed.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final error = ref.watch(rssArticlesProvider).errors[feed.id];
    final unread = ref.watch(
      unreadCountProvider((categoryId: null, feedId: feed.id)),
    );

    return ListTile(
      contentPadding: const EdgeInsets.only(left: 46, right: 4),
      onTap: () => context.push(RssRoutes.feed(feed.id)),
      title: Text(feed.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        error ?? Uri.parse(feed.url).host,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: error == null ? Colors.white54 : Colors.orange),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (error != null)
            const Icon(Icons.warning_amber, color: Colors.orange, size: 20),
          if (unread > 0)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Badge(
                backgroundColor: Theme.of(context).colorScheme.primary,
                textColor: Colors.white,
                label: Text('$unread'),
              ),
            ),
          PopupMenuButton<_FeedAction>(
            onSelected: (a) => _onAction(context, ref, a),
            itemBuilder: (_) => const [
              PopupMenuItem(value: _FeedAction.rename, child: Text('Rename')),
              PopupMenuItem(
                value: _FeedAction.move,
                child: Text('Move to category'),
              ),
              PopupMenuItem(
                value: _FeedAction.delete,
                child: Text('Unsubscribe'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
