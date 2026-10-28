/// A subscribed feed.
class RssFeed {
  const RssFeed({
    required this.id,
    required this.url,
    required this.title,
    required this.categoryId,
    required this.addedAt,
    this.siteUrl,
  });

  final String id;

  /// URL of the RSS/Atom document.
  final String url;
  final String title;
  final String categoryId;
  final DateTime addedAt;

  /// Home page of the site, if the feed declares one.
  final String? siteUrl;

  RssFeed copyWith({String? title, String? categoryId}) => RssFeed(
    id: id,
    url: url,
    title: title ?? this.title,
    categoryId: categoryId ?? this.categoryId,
    addedAt: addedAt,
    siteUrl: siteUrl,
  );
}
