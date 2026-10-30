import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/text_direction.dart';

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
          for (final (:category, :depth) in library.tree())
            _CategorySection(category: category, depth: depth),
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

enum _CategoryAction { addFeed, addFolder, move, rename, delete }

/// Picks a folder from the tree (indented). [exclude] folders can't be
/// chosen; [topLevel] adds a "Top level" choice (returned as '').
Future<String?> pickFolder(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  String? current,
  Set<String> exclude = const {},
  bool topLevel = false,
}) {
  final tree = ref.read(rssLibraryProvider).tree();
  Widget option(String value, String label, int depth, {bool enabled = true}) =>
      SimpleDialogOption(
        onPressed: enabled ? () => Navigator.pop(context, value) : null,
        padding: EdgeInsets.fromLTRB(24.0 + depth * 20, 12, 24, 12),
        child: Row(
          children: [
            Icon(
              value == (current ?? '')
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              size: 20,
              color: enabled ? null : Colors.white24,
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  color: enabled ? null : Colors.white38,
                ),
              ),
            ),
          ],
        ),
      );
  return showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(title),
      children: [
        if (topLevel) option('', 'Top level', 0),
        for (final (:category, :depth) in tree)
          option(
            category.id,
            category.name,
            depth,
            enabled: !exclude.contains(category.id),
          ),
      ],
    ),
  );
}

class _CategorySection extends ConsumerWidget {
  const _CategorySection({required this.category, required this.depth});

  final FeedCategory category;

  /// 0 for top-level folders.
  final int depth;

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    _CategoryAction action,
  ) async {
    final notifier = ref.read(rssLibraryProvider.notifier);
    switch (action) {
      case _CategoryAction.addFeed:
        await showAddFeedSheet(context, initialCategoryId: category.id);
      case _CategoryAction.addFolder:
        final name = await showTextInputDialog(
          context,
          title: 'New folder in "${category.name}"',
          hint: 'e.g. AI, Phones, Gaming',
          confirmLabel: 'Create',
        );
        if (name != null) {
          await notifier.addCategory(name, parentId: category.id);
        }
      case _CategoryAction.move:
        final library = ref.read(rssLibraryProvider);
        final target = await pickFolder(
          context,
          ref,
          title: 'Move "${category.name}" into',
          current: category.parentId,
          exclude: library.subtreeIds(category.id),
          topLevel: true,
        );
        if (target != null) {
          await notifier.moveCategory(
            category.id,
            target.isEmpty ? null : target,
          );
        }
      case _CategoryAction.rename:
        final name = await showTextInputDialog(
          context,
          title: 'Rename category',
          initialValue: category.name,
        );
        if (name != null) await notifier.renameCategory(category.id, name);
      case _CategoryAction.delete:
        final library = ref.read(rssLibraryProvider);
        final count = library.feedsIn(category.id).length;
        final folders = library.childrenOf(category.id).length;
        final ok = await showConfirmDialog(
          context,
          title: 'Delete "${category.name}"?',
          message: [
            count == 0
                ? 'It has no feeds of its own.'
                : 'Its $count ${count == 1 ? 'feed' : 'feeds'} will be '
                      'unsubscribed too. Move feeds to another folder first '
                      'to keep them.',
            if (folders > 0)
              'Its ${folders == 1 ? 'sub-folder moves' : '$folders sub-folders move'} '
                  'up a level.',
          ].join(' '),
        );
        if (ok) await notifier.deleteCategory(category.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(rssLibraryProvider);
    final feeds = library.feedsIn(category.id);
    final hasFolders = library.childrenOf(category.id).isNotEmpty;
    final indent = depth * 20.0;
    final unread = ref.watch(
      unreadCountProvider((categoryId: category.id, feedId: null)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16 + indent, 16, 4, 4),
          child: Row(
            children: [
              Icon(
                depth > 0 ? Icons.subdirectory_arrow_right : Icons.folder,
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
                    value: _CategoryAction.addFolder,
                    child: Text('New sub-folder'),
                  ),
                  PopupMenuItem(
                    value: _CategoryAction.move,
                    child: Text('Move into…'),
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
        if (feeds.isEmpty && !hasFolders)
          Padding(
            padding: EdgeInsets.fromLTRB(46 + indent, 0, 16, 8),
            child: const Text(
              'No feeds yet',
              style: TextStyle(color: Colors.white38),
            ),
          ),
        for (final feed in feeds) _FeedTile(feed: feed, indent: indent),
        if (!hasFolders) const Divider(height: 16),
      ],
    );
  }
}

enum _FeedAction { rename, move, delete }

class _FeedTile extends ConsumerWidget {
  const _FeedTile({required this.feed, this.indent = 0});

  final RssFeed feed;
  final double indent;

  Future<void> _move(BuildContext context, WidgetRef ref) async {
    final target = await pickFolder(
      context,
      ref,
      title: 'Move to',
      current: feed.categoryId,
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
    final health = ref.watch(rssArticlesProvider).health[feed.id];
    final broken = health?.isBroken(DateTime.now()) ?? false;
    // Recent, temporary trouble is shown quietly; days of failures in orange.
    final error = health == null
        ? null
        : broken
        ? health.lastError
        : 'Temporarily unavailable, will retry · ${health.lastError}';
    final unread = ref.watch(
      unreadCountProvider((categoryId: null, feedId: feed.id)),
    );

    return ListTile(
      contentPadding: EdgeInsets.only(left: 46 + indent, right: 4),
      onTap: () => context.push(RssRoutes.feed(feed.id)),
      title: Text(
        feed.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        // Correct word order for Arabic names, kept left-aligned in the list.
        textDirection: textDirectionOf(feed.title),
        textAlign: TextAlign.left,
      ),
      subtitle: Text(
        error ?? Uri.parse(feed.url).host,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: broken ? Colors.orange : Colors.white54),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (broken)
            const Icon(Icons.warning_amber, color: Colors.orange, size: 20)
          else if (error != null)
            const Icon(Icons.schedule, color: Colors.white38, size: 18),
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
