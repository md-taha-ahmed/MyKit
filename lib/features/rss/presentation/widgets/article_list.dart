import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../rss_routes.dart';
import '../providers/rss_providers.dart';
import 'article_actions.dart';
import 'article_tile.dart';

/// Pull-to-refresh list of articles for [filter].
class ArticleList extends ConsumerWidget {
  const ArticleList({super.key, required this.filter, required this.empty});

  final ArticleFilter filter;

  /// Shown when there are no articles.
  final Widget empty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final articles = ref.watch(filteredArticlesProvider(filter));
    final read = ref.watch(rssReadIdsProvider);
    final library = ref.watch(rssLibraryProvider);
    final reactions = ref.watch(rssReactionsProvider);
    final fromSaved = filter.categoryId == savedArticlesFilter;

    Future<void> refresh() => ref.read(rssArticlesProvider.notifier).refresh();

    if (articles.isEmpty) {
      return RefreshIndicator(
        onRefresh: refresh,
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(height: c.maxHeight, child: empty),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: articles.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, indent: 16, endIndent: 16),
        itemBuilder: (context, i) {
          final article = articles[i];
          final saved = reactions.isSaved(article.id);
          // Swipe right → bookmark, swipe left → delete (Saved: un-bookmark).
          return Dismissible(
            key: ValueKey(article.id),
            background: SwipeBackground(
              icon: saved ? Icons.bookmark_remove : Icons.bookmark_add,
              label: saved ? 'Unsave' : 'Save',
              color: const Color(0xFF1F6F4A),
              alignment: Alignment.centerLeft,
            ),
            secondaryBackground: SwipeBackground(
              icon: fromSaved ? Icons.bookmark_remove : Icons.delete_outline,
              label: fromSaved ? 'Remove' : 'Delete',
              color: const Color(0xFF8E2B2B),
              alignment: Alignment.centerRight,
            ),
            confirmDismiss: (direction) async {
              if (direction == DismissDirection.startToEnd) {
                await toggleSaveArticle(context, ref, article);
                return false; // stays in the list
              }
              return true;
            },
            onDismissed: (_) =>
                deleteArticle(context, ref, article, fromSaved: fromSaved),
            child: ArticleTile(
              article: article,
              feedTitle: library.feedById(article.feedId)?.title ?? '',
              isVideo: library.feedById(article.feedId)?.isYoutube ?? false,
              isRead: read.contains(article.id),
              isSaved: saved,
              isLiked: reactions.isLiked(article.id),
              onTap: () => context.push(RssRoutes.article(article.id)),
            ),
          );
        },
      ),
    );
  }
}

/// Centered icon + message (+ optional action) for empty states.
class RssEmptyState extends StatelessWidget {
  const RssEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.white24),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60),
            ),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}
