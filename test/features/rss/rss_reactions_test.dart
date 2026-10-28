import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykit/core/storage/shared_preferences_provider.dart';
import 'package:mykit/features/rss/domain/entities/feed_article.dart';
import 'package:mykit/features/rss/domain/repositories/rss_repository.dart';
import 'package:mykit/features/rss/presentation/providers/rss_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

FeedArticle _article(String key, int day) => FeedArticle(
  id: key,
  feedId: '',
  title: key,
  publishedAt: DateTime(2026, 10, day),
);

void main() {
  test(
    'delete hides (with undo); bookmarks and likes are filterable',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(c.dispose);

      // Subscribing ingests the parsed articles straight into the cache.
      await c
          .read(rssLibraryProvider.notifier)
          .addFeed(
            preview: FeedPreview(
              url: 'https://example.com/feed',
              feed: ParsedFeed(
                title: 'Example',
                articles: [
                  _article('a', 1),
                  _article('b', 3),
                  _article('c', 2),
                ],
              ),
            ),
            title: '',
            categoryId: c.read(rssLibraryProvider).categories.first.id,
          );

      const all = (categoryId: null, feedId: null);
      List<String> titles([ArticleFilter f = all]) =>
          c.read(filteredArticlesProvider(f)).map((a) => a.title).toList();
      FeedArticle byTitle(String t) =>
          c.read(rssArticlesProvider).articles.firstWhere((a) => a.title == t);

      expect(titles(), ['b', 'c', 'a']); // newest first

      final reactions = c.read(rssReactionsProvider.notifier);
      await reactions.delete(byTitle('c').id);
      expect(titles(), ['b', 'a']);
      await reactions.undoDelete(byTitle('c').id);
      expect(titles(), ['b', 'c', 'a']);

      expect(await reactions.toggleSave(byTitle('a')), isTrue);
      await reactions.like(byTitle('b').id);
      expect(titles((categoryId: savedArticlesFilter, feedId: null)), ['a']);
      expect(titles((categoryId: likedArticlesFilter, feedId: null)), ['b']);

      // A bookmark outlives its feed and the article cache.
      final savedId = byTitle('a').id;
      await c
          .read(rssLibraryProvider.notifier)
          .deleteFeed(c.read(rssLibraryProvider).feeds.single.id);
      expect(c.read(rssArticlesProvider).articles, isEmpty);
      expect(c.read(articleByIdProvider(savedId))?.title, 'a');
      expect(prefs.getString('rss.saved.v1'), contains('"title":"a"'));
    },
  );
}
