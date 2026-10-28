import '../../domain/entities/feed_article.dart';
import '../../domain/entities/feed_category.dart';
import '../../domain/entities/rss_feed.dart';
import '../../domain/entities/youtube_channel.dart';
import '../../domain/repositories/rss_repository.dart';
import '../datasources/rss_local_data_source.dart';
import '../datasources/rss_remote_data_source.dart';
import '../datasources/youtube_subscriptions_data_source.dart';
import '../models/rss_models.dart';

class RssRepositoryImpl implements RssRepository {
  RssRepositoryImpl(this._local, this._remote, this._youtube);

  final RssLocalDataSource _local;
  final RssRemoteDataSource _remote;
  final YoutubeSubscriptionsDataSource _youtube;

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

  @override
  bool get youtubeConfigured => _youtube.isConfigured;

  @override
  bool get youtubeSignedIn => _youtube.isSignedIn;

  @override
  Future<void> configureYoutube(String clientId, String clientSecret) =>
      _youtube.configure(clientId, clientSecret);

  @override
  Future<List<YoutubeChannel>> youtubeSubscriptions() =>
      _youtube.fetchSubscriptions();

  @override
  Future<void> disconnectYoutube() => _youtube.disconnect();

  @override
  List<FeedArticle> getSavedArticles() =>
      _local.readSaved().map(RssModels.articleFromJson).toList();

  @override
  Future<void> saveSavedArticles(List<FeedArticle> articles) =>
      _local.writeSaved(articles.map(RssModels.articleToJson).toList());

  @override
  Set<String> getLikedIds() => _local.readLiked();

  @override
  Future<void> saveLikedIds(Set<String> ids) => _local.writeLiked(ids);

  @override
  Set<String> getHiddenIds() => _local.readHidden();

  @override
  Future<void> saveHiddenIds(Set<String> ids) => _local.writeHidden(ids);
}
