import '../../domain/entities/feed_article.dart';
import '../../domain/entities/feed_category.dart';
import '../../domain/entities/rss_feed.dart';
import '../../domain/repositories/rss_repository.dart';
import '../datasources/rss_local_data_source.dart';
import '../datasources/rss_remote_data_source.dart';
import '../models/rss_models.dart';

class RssRepositoryImpl implements RssRepository {
  RssRepositoryImpl(this._local, this._remote);

  final RssLocalDataSource _local;
  final RssRemoteDataSource _remote;

  @override
  List<FeedCategory> getCategories() =>
      _local.readCategories().map(RssModels.categoryFromJson).toList();

  @override
  Future<void> saveCategories(List<FeedCategory> categories) =>
      _local.writeCategories(categories.map(RssModels.categoryToJson).toList());

  @override
  List<RssFeed> getFeeds() =>
      _local.readFeeds().map(RssModels.feedFromJson).toList();

  @override
  Future<void> saveFeeds(List<RssFeed> feeds) =>
      _local.writeFeeds(feeds.map(RssModels.feedToJson).toList());

  @override
  Future<FeedPreview> preview(String url) => _remote.discover(url);

  @override
  Future<ParsedFeed> fetch(RssFeed feed) => _remote.fetch(feed.url);

  @override
  List<FeedArticle> getCachedArticles() =>
      _local.readArticles().map(RssModels.articleFromJson).toList();

  @override
  Future<void> saveCachedArticles(List<FeedArticle> articles) =>
      _local.writeArticles(articles.map(RssModels.articleToJson).toList());

  @override
  Set<String> getReadIds() => _local.readReadIds();

  @override
  Future<void> saveReadIds(Set<String> ids) => _local.writeReadIds(ids);
}
