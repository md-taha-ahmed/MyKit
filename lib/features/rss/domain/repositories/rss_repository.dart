import '../entities/feed_article.dart';
import '../entities/feed_category.dart';
import '../entities/rss_feed.dart';

/// Thrown when a URL can't be turned into a feed.
class FeedException implements Exception {
  const FeedException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A feed URL that was resolved and parsed successfully.
class FeedPreview {
  const FeedPreview({required this.url, required this.feed});

  /// Final feed URL (may differ from the input when discovered from a page).
  final String url;
  final ParsedFeed feed;
}

abstract interface class RssRepository {
  // Library (categories + feeds)
  List<FeedCategory> getCategories();
  Future<void> saveCategories(List<FeedCategory> categories);
  List<RssFeed> getFeeds();
  Future<void> saveFeeds(List<RssFeed> feeds);

  // Network
  /// Fetches [url]; if it's a web page, discovers its feed link.
  Future<FeedPreview> preview(String url);
  Future<ParsedFeed> fetch(RssFeed feed);

  // Article cache + read state
  List<FeedArticle> getCachedArticles();
  Future<void> saveCachedArticles(List<FeedArticle> articles);
  Set<String> getReadIds();
  Future<void> saveReadIds(Set<String> ids);
}
