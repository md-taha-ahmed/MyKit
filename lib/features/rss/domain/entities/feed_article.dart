/// One entry from a feed.
class FeedArticle {
  const FeedArticle({
    required this.id,
    required this.feedId,
    required this.title,
    this.link,
    this.summary = '',
    this.content = '',
    this.imageUrl,
    this.author,
    this.publishedAt,
  });

  /// Stable across refreshes: feed id + guid/link/title.
  final String id;
  final String feedId;
  final String title;
  final String? link;

  /// Short plain-text teaser.
  final String summary;

  /// Plain-text body (may be the same as [summary] for short feeds).
  final String content;
  final String? imageUrl;
  final String? author;
  final DateTime? publishedAt;

  /// Binds a freshly parsed article to [feedId], namespacing its id.
  FeedArticle forFeed(String feedId) => FeedArticle(
    id: '$feedId::$id',
    feedId: feedId,
    title: title,
    link: link,
    summary: summary,
    content: content,
    imageUrl: imageUrl,
    author: author,
    publishedAt: publishedAt,
  );
}

/// Parsed feed document, before it's saved as an [RssFeed].
class ParsedFeed {
  const ParsedFeed({required this.title, required this.articles, this.siteUrl});

  final String title;
  final String? siteUrl;

  /// Articles with an empty `feedId` (assigned when stored).
  final List<FeedArticle> articles;
}
