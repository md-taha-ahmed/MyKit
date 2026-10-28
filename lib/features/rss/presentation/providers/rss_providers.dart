import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../../../core/storage/shared_preferences_provider.dart';
import '../../data/datasources/rss_local_data_source.dart';
import '../../data/datasources/rss_remote_data_source.dart';
import '../../data/repositories/rss_repository_impl.dart';
import '../../domain/entities/feed_article.dart';
import '../../domain/entities/feed_category.dart';
import '../../domain/entities/rss_feed.dart';
import '../../domain/repositories/rss_repository.dart';

const _uuid = Uuid();

// ---------------------------------------------------------------------------
// Dependencies
// ---------------------------------------------------------------------------

final rssRepositoryProvider = Provider<RssRepository>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return RssRepositoryImpl(
    RssLocalDataSource(ref.watch(sharedPreferencesProvider)),
    RssRemoteDataSource(client),
  );
});

// ---------------------------------------------------------------------------
// Library: categories + feeds
// ---------------------------------------------------------------------------

class RssLibrary {
  const RssLibrary({required this.categories, required this.feeds});

  final List<FeedCategory> categories;
  final List<RssFeed> feeds;

  List<RssFeed> feedsIn(String categoryId) =>
      feeds.where((f) => f.categoryId == categoryId).toList();

  RssFeed? feedById(String id) {
    for (final f in feeds) {
      if (f.id == id) return f;
    }
    return null;
  }

  FeedCategory? categoryById(String id) {
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }
}

final rssLibraryProvider = NotifierProvider<RssLibraryNotifier, RssLibrary>(
  RssLibraryNotifier.new,
);

class RssLibraryNotifier extends Notifier<RssLibrary> {
  RssRepository get _repo => ref.read(rssRepositoryProvider);

  @override
  RssLibrary build() {
    var categories = _repo.getCategories();
    if (categories.isEmpty) {
      categories = [FeedCategory(id: _uuid.v4(), name: 'General')];
      _repo.saveCategories(categories);
    }
    return RssLibrary(categories: categories, feeds: _repo.getFeeds());
  }

  Future<void> _set({
    List<FeedCategory>? categories,
    List<RssFeed>? feeds,
  }) async {
    state = RssLibrary(
      categories: categories ?? state.categories,
      feeds: feeds ?? state.feeds,
    );
    if (categories != null) await _repo.saveCategories(categories);
    if (feeds != null) await _repo.saveFeeds(feeds);
  }

  // Categories ---------------------------------------------------------------

  Future<FeedCategory> addCategory(String name) async {
    final category = FeedCategory(id: _uuid.v4(), name: name.trim());
    await _set(categories: [...state.categories, category]);
    return category;
  }

  Future<void> renameCategory(String id, String name) => _set(
    categories: [
      for (final c in state.categories)
        c.id == id ? c.copyWith(name: name.trim()) : c,
    ],
  );

  /// Deletes the category together with its feeds and their articles.
  Future<void> deleteCategory(String id) async {
    final removed = state.feedsIn(id).map((f) => f.id).toSet();
    await _set(
      categories: state.categories.where((c) => c.id != id).toList(),
      feeds: state.feeds.where((f) => f.categoryId != id).toList(),
    );
    if (state.categories.isEmpty) await addCategory('General');
    await ref.read(rssArticlesProvider.notifier).removeFeeds(removed);
  }

  // Feeds --------------------------------------------------------------------

  bool isSubscribed(String url) => state.feeds.any((f) => f.url == url);

  Future<RssFeed> addFeed({
    required FeedPreview preview,
    required String title,
    required String categoryId,
  }) async {
    final feed = RssFeed(
      id: _uuid.v4(),
      url: preview.url,
      title: title.trim().isEmpty ? preview.feed.title : title.trim(),
      categoryId: categoryId,
      addedAt: DateTime.now(),
      siteUrl: preview.feed.siteUrl,
    );
    await _set(feeds: [...state.feeds, feed]);
    // Articles were already downloaded for the preview — use them right away.
    await ref.read(rssArticlesProvider.notifier).ingest(feed, preview.feed);
    return feed;
  }

  Future<void> updateFeed(RssFeed feed) =>
      _set(feeds: [for (final f in state.feeds) f.id == feed.id ? feed : f]);

  Future<void> deleteFeed(String id) async {
    await _set(feeds: state.feeds.where((f) => f.id != id).toList());
    await ref.read(rssArticlesProvider.notifier).removeFeeds({id});
  }
}

// ---------------------------------------------------------------------------
// Articles
// ---------------------------------------------------------------------------

class RssArticlesState {
  const RssArticlesState({
    this.articles = const [],
    this.refreshing = false,
    this.errors = const {},
    this.lastRefreshed,
  });

  final List<FeedArticle> articles;
  final bool refreshing;

  /// Last refresh error per feed id.
  final Map<String, String> errors;
  final DateTime? lastRefreshed;

  RssArticlesState copyWith({
    List<FeedArticle>? articles,
    bool? refreshing,
    Map<String, String>? errors,
    DateTime? lastRefreshed,
  }) => RssArticlesState(
    articles: articles ?? this.articles,
    refreshing: refreshing ?? this.refreshing,
    errors: errors ?? this.errors,
    lastRefreshed: lastRefreshed ?? this.lastRefreshed,
  );
}

final rssArticlesProvider =
    NotifierProvider<RssArticlesNotifier, RssArticlesState>(
      RssArticlesNotifier.new,
    );

class RssArticlesNotifier extends Notifier<RssArticlesState> {
  static const _maxPerFeed = 100;

  RssRepository get _repo => ref.read(rssRepositoryProvider);

  @override
  RssArticlesState build() =>
      RssArticlesState(articles: _repo.getCachedArticles());

  /// Downloads every feed in parallel. Feeds that fail keep their cache.
  Future<void> refresh() async {
    if (state.refreshing) return;
    final feeds = ref.read(rssLibraryProvider).feeds;
    state = state.copyWith(refreshing: true);

    final errors = <String, String>{};
    final fresh = <String, List<FeedArticle>>{};
    await Future.wait(
      feeds.map((feed) async {
        try {
          fresh[feed.id] = _bind(feed, await _repo.fetch(feed));
        } catch (e) {
          errors[feed.id] = e.toString();
        }
      }),
    );

    // Re-read: feeds may have been added/removed while we were fetching.
    final feedIds = ref.read(rssLibraryProvider).feeds.map((f) => f.id).toSet();
    final merged = <FeedArticle>[
      for (final a in state.articles)
        if (feedIds.contains(a.feedId) && !fresh.containsKey(a.feedId)) a,
      for (final e in fresh.entries)
        if (feedIds.contains(e.key)) ...e.value,
    ];

    state = RssArticlesState(
      articles: merged,
      errors: errors,
      lastRefreshed: DateTime.now(),
    );
    await _repo.saveCachedArticles(merged);
  }

  /// Stores articles of a feed that was just fetched (e.g. when added).
  Future<void> ingest(RssFeed feed, ParsedFeed parsed) async {
    final articles = [
      ...state.articles.where((a) => a.feedId != feed.id),
      ..._bind(feed, parsed),
    ];
    state = state.copyWith(articles: articles);
    await _repo.saveCachedArticles(articles);
  }

  Future<void> removeFeeds(Set<String> feedIds) async {
    if (feedIds.isEmpty) return;
    final articles = state.articles
        .where((a) => !feedIds.contains(a.feedId))
        .toList();
    state = state.copyWith(
      articles: articles,
      errors: {...state.errors}..removeWhere((k, _) => feedIds.contains(k)),
    );
    await _repo.saveCachedArticles(articles);
  }

  static List<FeedArticle> _bind(RssFeed feed, ParsedFeed parsed) {
    final seen = <String>{};
    return [
      for (final a in parsed.articles.take(_maxPerFeed))
        if (seen.add(a.id)) a.forFeed(feed.id),
    ];
  }
}

// ---------------------------------------------------------------------------
// Read state
// ---------------------------------------------------------------------------

final rssReadIdsProvider = NotifierProvider<RssReadIdsNotifier, Set<String>>(
  RssReadIdsNotifier.new,
);

class RssReadIdsNotifier extends Notifier<Set<String>> {
  static const _maxStored = 5000;

  RssRepository get _repo => ref.read(rssRepositoryProvider);

  @override
  Set<String> build() => _repo.getReadIds();

  Future<void> markRead(Iterable<String> ids) async {
    final next = {...state, ...ids};
    if (next.length == state.length) return;
    // Keep storage bounded: forget read marks of articles no longer cached.
    if (next.length > _maxStored) {
      final live = ref.read(rssArticlesProvider).articles.map((a) => a.id);
      next.retainAll(live.toSet());
    }
    state = next;
    await _repo.saveReadIds(next);
  }

  Future<void> markUnread(String id) async {
    state = {...state}..remove(id);
    await _repo.saveReadIds(state);
  }
}

// ---------------------------------------------------------------------------
// Views
// ---------------------------------------------------------------------------

/// Which articles to show: everything, one category, or one feed.
typedef ArticleFilter = ({String? categoryId, String? feedId});

const allArticles = (categoryId: null, feedId: null);

/// Selected chip on the RSS home screen (`null` = All).
final selectedRssCategoryProvider =
    NotifierProvider<SelectedRssCategoryNotifier, String?>(
      SelectedRssCategoryNotifier.new,
    );

class SelectedRssCategoryNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? categoryId) => state = categoryId;
}

/// Newest-first articles matching [ArticleFilter].
final filteredArticlesProvider =
    Provider.family<List<FeedArticle>, ArticleFilter>((ref, filter) {
      final library = ref.watch(rssLibraryProvider);
      final articles = ref.watch(rssArticlesProvider).articles;

      final Set<String> feedIds;
      if (filter.feedId != null) {
        feedIds = {filter.feedId!};
      } else if (filter.categoryId != null) {
        feedIds = library.feedsIn(filter.categoryId!).map((f) => f.id).toSet();
      } else {
        feedIds = library.feeds.map((f) => f.id).toSet();
      }

      final result = articles.where((a) => feedIds.contains(a.feedId)).toList()
        ..sort((a, b) {
          final da = a.publishedAt, db = b.publishedAt;
          if (da == null && db == null) return 0;
          if (da == null) return 1;
          if (db == null) return -1;
          return db.compareTo(da);
        });
      return result;
    });

/// Unread article count for a filter.
final unreadCountProvider = Provider.family<int, ArticleFilter>((ref, filter) {
  final read = ref.watch(rssReadIdsProvider);
  return ref
      .watch(filteredArticlesProvider(filter))
      .where((a) => !read.contains(a.id))
      .length;
});
