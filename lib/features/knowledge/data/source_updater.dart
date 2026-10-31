import 'package:http/http.dart' as http;

import '../../rss/data/datasources/rss_remote_data_source.dart';
import '../domain/knowledge_models.dart';
import 'knowledge_remote.dart';
import 'knowledge_store.dart';

/// What a check found.
class SourceUpdate {
  const SourceUpdate({
    required this.items,
    required this.failed,
    required this.found,
  });

  /// Every item, newest first (what's saved).
  final List<SourceItem> items;

  /// Sources that couldn't be checked.
  final Set<String> failed;

  /// Items seen for the first time in this check (not counting a source's
  /// very first check).
  final List<SourceItem> found;
}

/// Checks the followed sites and channels for new articles: RSS where the
/// site has it, otherwise the links on its page. Used by the app and by the
/// background check (WorkManager), so it only needs the store and a client.
class SourceUpdater {
  SourceUpdater(this._store, http.Client client)
    : _rss = RssRemoteDataSource(client),
      _remote = KnowledgeRemote(client);

  final KnowledgeStore _store;
  final RssRemoteDataSource _rss;
  final KnowledgeRemote _remote;

  static const _perSource = 30;

  Future<SourceUpdate> run() async {
    final sources = _store.sources;
    final current = _store.items;
    final old = {for (final i in current) i.url: i};
    final checkedBefore = {for (final i in current) i.sourceId};
    final failed = <String>{};
    final fresh = <SourceItem>[];
    final found = <SourceItem>[];

    await Future.wait([
      for (final s in sources)
        () async {
          try {
            final links = <({String title, String url, DateTime? date})>[];
            if (s.feedUrl case final feed?) {
              for (final a in (await _rss.fetch(feed)).articles) {
                if (a.link case final link?) {
                  links.add((title: a.title, url: link, date: a.publishedAt));
                }
              }
            } else {
              for (final l in (await _remote.watch(s.url)).links) {
                links.add((title: l.title, url: l.url, date: null));
              }
            }
            final now = DateTime.now();
            for (final (i, l) in links.take(_perSource).indexed) {
              if (old[l.url] case final previous?) {
                fresh.add(previous);
                continue;
              }
              final item = SourceItem(
                sourceId: s.id,
                title: l.title,
                url: l.url,
                // Keeps page order for links seen at the same time.
                date: l.date ?? now.subtract(Duration(seconds: i)),
                isNew: checkedBefore.contains(s.id),
              );
              fresh.add(item);
              if (item.isNew) found.add(item);
            }
          } catch (_) {
            failed.add(s.id);
            fresh.addAll(current.where((i) => i.sourceId == s.id));
          }
        }(),
    ]);

    final ids = {for (final s in sources) s.id};
    final items = fresh.where((i) => ids.contains(i.sourceId)).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    await _store.saveItems(items);
    await _store.saveLastSourceCheck(DateTime.now());
    return SourceUpdate(items: items, failed: failed, found: found);
  }
}
