import '../../domain/entities/feed_article.dart';
import '../../domain/entities/feed_category.dart';
import '../../domain/entities/rss_feed.dart';

/// JSON mapping for RSS entities (local storage only).
abstract final class RssModels {
  static Map<String, dynamic> categoryToJson(FeedCategory c) => {
    'id': c.id,
    'name': c.name,
  };

  static FeedCategory categoryFromJson(Map<String, dynamic> j) =>
      FeedCategory(id: j['id'] as String, name: j['name'] as String);

  static Map<String, dynamic> feedToJson(RssFeed f) => {
    'id': f.id,
    'url': f.url,
    'title': f.title,
    'categoryId': f.categoryId,
    'addedAt': f.addedAt.toIso8601String(),
    'siteUrl': f.siteUrl,
  };

  static RssFeed feedFromJson(Map<String, dynamic> j) => RssFeed(
    id: j['id'] as String,
    url: j['url'] as String,
    title: j['title'] as String,
    categoryId: j['categoryId'] as String,
    addedAt: DateTime.tryParse(j['addedAt'] as String? ?? '') ?? DateTime.now(),
    siteUrl: j['siteUrl'] as String?,
  );

  static Map<String, dynamic> articleToJson(FeedArticle a) => {
    'id': a.id,
    'feedId': a.feedId,
    'title': a.title,
    'link': a.link,
    'summary': a.summary,
    'content': a.content,
    'imageUrl': a.imageUrl,
    'author': a.author,
    'publishedAt': a.publishedAt?.toIso8601String(),
  };

  static FeedArticle articleFromJson(Map<String, dynamic> j) => FeedArticle(
    id: j['id'] as String,
    feedId: j['feedId'] as String,
    title: j['title'] as String,
    link: j['link'] as String?,
    summary: j['summary'] as String? ?? '',
    content: j['content'] as String? ?? '',
    imageUrl: j['imageUrl'] as String?,
    author: j['author'] as String?,
    publishedAt: DateTime.tryParse(j['publishedAt'] as String? ?? ''),
  );
}
