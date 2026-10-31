import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../../core/i18n/i18n.dart';
import '../../../../core/storage/app_directories.dart';
import '../../../../core/storage/shared_preferences_provider.dart';
import '../../data/datasources/offline_article_store.dart';
import '../../domain/entities/feed_article.dart';
import 'article_ai_providers.dart';
import 'rss_providers.dart';

final offlineStoreProvider = Provider<OfflineArticleStore>(
  (ref) => OfflineArticleStore(ref.watch(appDocumentsDirectoryProvider)),
);

/// The saved full text of an article, if it was downloaded for offline.
final offlineTextProvider = FutureProvider.autoDispose.family<String?, String>((
  ref,
  articleId,
) {
  ref.watch(offlineDownloadProvider.select((s) => s.savedCount));
  return ref.read(offlineStoreProvider).text(articleId);
});

class OfflineDownloadState {
  const OfflineDownloadState({
    this.running = false,
    this.done = 0,
    this.total = 0,
    this.savedCount = 0,
    this.bytes = 0,
    this.autoUpdate = false,
    this.limit = 600,
    this.lastRun,
    this.message,
  });

  final bool running;
  final int done;
  final int total;

  /// Articles with a saved copy, and the space used (texts + images).
  final int savedCount;
  final int bytes;

  /// Also save new articles after every refresh.
  final bool autoUpdate;

  /// How many of the newest articles to save (0 = all of them).
  final int limit;
  final DateTime? lastRun;

  /// Result of the last download ("Saved 120 articles", or what failed).
  final String? message;

  double get progress => total == 0 ? 0 : done / total;

  OfflineDownloadState copyWith({
    bool? running,
    int? done,
    int? total,
    int? savedCount,
    int? bytes,
    bool? autoUpdate,
    int? limit,
    DateTime? lastRun,
    String? Function()? message,
  }) => OfflineDownloadState(
    running: running ?? this.running,
    done: done ?? this.done,
    total: total ?? this.total,
    savedCount: savedCount ?? this.savedCount,
    bytes: bytes ?? this.bytes,
    autoUpdate: autoUpdate ?? this.autoUpdate,
    limit: limit ?? this.limit,
    lastRun: lastRun ?? this.lastRun,
    message: message != null ? message() : this.message,
  );
}

final offlineDownloadProvider =
    NotifierProvider<OfflineDownloadNotifier, OfflineDownloadState>(
      OfflineDownloadNotifier.new,
    );

/// Saves articles (full text from the web page when the feed only has a
/// teaser, and their images) so they can be read with no connection — e.g.
/// before a trip.
class OfflineDownloadNotifier extends Notifier<OfflineDownloadState> {
  static const _autoKey = 'rss.offline.auto';
  static const _lastRunKey = 'rss.offline.lastRun';

  static const _limitKey = 'rss.offline.limit';

  bool _cancelled = false;
  http.Client? _client;

  OfflineArticleStore get _store => ref.read(offlineStoreProvider);

  @override
  OfflineDownloadState build() {
    final prefs = ref.read(sharedPreferencesProvider);
    final last = prefs.getInt(_lastRunKey);
    Future.microtask(_refreshUsage);
    ref.onDispose(() => _client?.close());
    return OfflineDownloadState(
      autoUpdate: prefs.getBool(_autoKey) ?? false,
      limit: prefs.getInt(_limitKey) ?? 600,
      lastRun: last == null ? null : DateTime.fromMillisecondsSinceEpoch(last),
    );
  }

  Future<void> setAutoUpdate(bool on) async {
    await ref.read(sharedPreferencesProvider).setBool(_autoKey, on);
    state = state.copyWith(autoUpdate: on);
  }

  /// How many of the newest articles to save; 0 saves all of them.
  Future<void> setLimit(int limit) async {
    final value = limit < 0 ? 0 : limit;
    await ref.read(sharedPreferencesProvider).setInt(_limitKey, value);
    state = state.copyWith(limit: value);
  }

  void cancel() => _cancelled = true;

  /// Refreshes the feeds, then saves the newest articles matching [filter]
  /// (all feeds by default) with or without their images.
  Future<void> download({
    ArticleFilter filter = allArticles,
    bool images = true,
    bool refreshFirst = true,
  }) async {
    if (state.running) return;
    _cancelled = false;
    state = state.copyWith(
      running: true,
      done: 0,
      total: 0,
      message: () => null,
    );
    try {
      if (refreshFirst) await ref.read(rssArticlesProvider.notifier).refresh();
      final matching = ref.read(filteredArticlesProvider(filter));
      final articles = state.limit == 0
          ? matching
          : matching.take(state.limit).toList();
      state = state.copyWith(total: articles.length);

      final client = _client ??= http.Client();
      final library = ref.read(rssLibraryProvider);
      var failed = 0;
      await forEachLimited(
        articles,
        (a) async {
          if (_cancelled) return;
          final video = library.feedById(a.feedId)?.isYoutube ?? false;
          final ok = await _save(a, client, images: images, video: video);
          if (!ok) failed++;
          state = state.copyWith(done: state.done + 1);
        },
        concurrency: 6,
        perKey: 3,
        keyOf: (a) => Uri.tryParse(a.link ?? '')?.host ?? '',
      );

      final now = DateTime.now();
      await ref
          .read(sharedPreferencesProvider)
          .setInt(_lastRunKey, now.millisecondsSinceEpoch);
      final saved = state.done - failed;
      state = state.copyWith(
        lastRun: now,
        message: () => _cancelled
            ? tr('Stopped. {saved} articles saved.', {'saved': saved})
            : failed == 0
            ? tr('Saved {saved} articles for offline reading.', {
                'saved': saved,
              })
            : tr('Saved {saved} articles; {failed} could not be downloaded.', {
                'saved': saved,
                'failed': failed,
              }),
      );
    } catch (e) {
      state = state.copyWith(
        message: () => tr('Download failed: {e}', {'e': e}),
      );
    } finally {
      state = state.copyWith(running: false);
      await _refreshUsage();
    }
  }

  /// Saves new articles after a refresh when auto-update is on.
  Future<void> afterRefresh() async {
    if (!state.autoUpdate || state.running) return;
    await download(refreshFirst: false);
  }

  /// Saves one article. Returns false if its text couldn't be had.
  Future<bool> _save(
    FeedArticle a,
    http.Client client, {
    required bool images,
    required bool video,
  }) async {
    var ok = true;
    if (!_store.hasText(a.id)) {
      final own = a.content.isNotEmpty ? a.content : a.summary;
      var text = own;
      final link = a.link;
      if (!video && own.length < 1500 && link != null) {
        final page = await ref.read(articleTextSourceProvider).fetch(link);
        if (page != null && page.length > own.length) text = page;
      }
      if (text.isNotEmpty) {
        await _store.saveText(a.id, text);
      } else {
        ok = false;
      }
    }
    final image = a.imageUrl;
    if (images && image != null && _store.image(image) == null) {
      try {
        final res = await client
            .get(Uri.parse(image))
            .timeout(const Duration(seconds: 20));
        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
          await _store.saveImage(image, res.bodyBytes);
        }
      } catch (_) {
        // The article is still readable without its picture.
      }
    }
    return ok;
  }

  /// Deletes every saved copy.
  Future<void> clear() async {
    await _store.clear();
    state = state.copyWith(message: () => tr('Offline copies deleted.'));
    await _refreshUsage();
  }

  /// Drops copies of articles that have left the feeds (bookmarks stay).
  Future<void> prune() async {
    final articles = [
      ...ref.read(rssArticlesProvider).articles,
      ...ref.read(rssReactionsProvider).saved,
    ];
    await _store.prune(
      keepIds: {for (final a in articles) a.id},
      keepImages: {
        for (final a in articles)
          if (a.imageUrl != null) a.imageUrl!,
      },
    );
    await _refreshUsage();
  }

  Future<void> _refreshUsage() async {
    final usage = await _store.usage();
    state = state.copyWith(savedCount: usage.articles, bytes: usage.bytes);
  }
}
