import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mykit/features/knowledge/data/knowledge_store.dart';
import 'package:mykit/features/knowledge/data/source_updater.dart';
import 'package:mykit/features/knowledge/domain/knowledge_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _page(List<int> ids) =>
    '<html><title>موقع</title><body>${[for (final id in ids) '<a href="/ar/answers/$id">سؤال رقم $id عن أحكام الصلاة</a>'].join()}<a href="/ar/tag/x">وسم لا يهم أبداً هنا</a></body></html>';

String _feed(List<int> ids) =>
    '<?xml version="1.0"?><rss version="2.0"><channel><title>ف</title>${[for (final id in ids) '<item><title>مقالة $id</title><link>https://feed.example/a/$id</link>'
          '<pubDate>Sat, 31 Oct 2026 0$id:00:00 GMT</pubDate></item>'].join()}</channel></rss>';

void main() {
  test(
    'first check fills the list quietly; later ones flag only new articles',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = KnowledgeStore(await SharedPreferences.getInstance());
      await store.saveSources(const [
        KnowledgeSource(
          id: 'page',
          name: 'صفحة',
          url: 'https://site.example/ar',
        ),
        KnowledgeSource(
          id: 'feed',
          name: 'خلاصة',
          url: 'https://feed.example',
          feedUrl: 'https://feed.example/rss',
        ),
      ]);

      var pageIds = [101, 102, 103];
      var feedIds = [1, 2];
      final client = MockClient((req) async {
        final body = req.url.host == 'site.example'
            ? _page(pageIds)
            : _feed(feedIds);
        return http.Response(
          body,
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      });

      final first = await SourceUpdater(store, client).run();
      expect(first.failed, isEmpty);
      expect(first.items.length, 5);
      expect(first.found, isEmpty);
      expect(first.items.any((i) => i.url.contains('/tag/')), isFalse);
      expect(store.lastSourceCheck, isNotNull);

      pageIds = [104, 101, 102, 103];
      feedIds = [3, 1, 2];
      final second = await SourceUpdater(store, client).run();
      expect(second.found.map((i) => i.url).toSet(), {
        'https://site.example/ar/answers/104',
        'https://feed.example/a/3',
      });
      expect(second.items.where((i) => i.isNew).length, 2);
      expect(store.items.length, 7);
    },
  );
}
