import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mykit/core/utils/charsets.dart';
import 'package:mykit/core/utils/text_direction.dart';
import 'package:mykit/features/rss/data/datasources/rss_remote_data_source.dart';
import 'package:mykit/features/rss/domain/entities/feed_article.dart';
import 'package:mykit/features/rss/domain/entities/feed_category.dart';
import 'package:mykit/features/rss/domain/entities/feed_health.dart';
import 'package:mykit/features/rss/domain/entities/rss_feed.dart';
import 'package:mykit/features/rss/domain/repositories/rss_repository.dart';
import 'package:mykit/features/rss/domain/services/reading_time.dart';
import 'package:mykit/features/rss/presentation/providers/article_ai_providers.dart';
import 'package:mykit/features/rss/presentation/providers/rss_providers.dart';

RssFeed _feed(String id, String category) => RssFeed(
  id: id,
  url: 'https://$id.example/feed',
  title: id,
  categoryId: category,
  addedAt: DateTime(2026),
);

const _rss =
    '<?xml version="1.0"?><rss version="2.0"><channel><title>T</title>'
    '<item><title>A</title><link>https://x/a</link></item></channel></rss>';

void main() {
  group('folders', () {
    final library = RssLibrary(
      categories: const [
        FeedCategory(id: 'tech', name: 'Tech'),
        FeedCategory(id: 'ai', name: 'AI', parentId: 'tech'),
        FeedCategory(id: 'phones', name: 'Phones', parentId: 'tech'),
        FeedCategory(id: 'llm', name: 'LLMs', parentId: 'ai'),
        FeedCategory(id: 'news', name: 'News'),
        FeedCategory(id: 'orphan', name: 'Orphan', parentId: 'deleted'),
      ],
      feeds: [
        _feed('verge', 'tech'),
        _feed('openai', 'ai'),
        _feed('anthropic', 'llm'),
        _feed('gsm', 'phones'),
        _feed('bbc', 'news'),
      ],
    );

    test('a folder shows the feeds of all its sub-folders', () {
      expect(library.feedsUnder('tech').map((f) => f.id).toSet(), {
        'verge',
        'openai',
        'anthropic',
        'gsm',
      });
      expect(library.feedsUnder('ai').map((f) => f.id).toSet(), {
        'openai',
        'anthropic',
      });
      expect(library.feedsIn('tech').map((f) => f.id), ['verge']);
    });

    test('tree order, depths, paths and orphans', () {
      expect(
        [for (final t in library.tree()) '${t.depth}${t.category.id}'],
        ['0tech', '1ai', '2llm', '1phones', '0news', '0orphan'],
      );
      expect(library.pathOf('llm'), 'Tech › AI › LLMs');
      expect(library.subtreeIds('ai'), {'ai', 'llm'});
    });
  });

  test('feed health: quiet for hiccups, reported when it keeps failing', () {
    final start = DateTime(2026, 10, 1);
    var h = FeedHealth.healthy;
    for (var i = 0; i < 5; i++) {
      h = h.failed('429', transient: true, now: start);
    }
    expect(h.isBroken(start.add(const Duration(days: 2))), isFalse);
    expect(h.isBroken(start.add(const Duration(days: 5))), isTrue);

    var gone = FeedHealth.healthy.failed('404', transient: false, now: start);
    expect(gone.isBroken(start.add(const Duration(days: 3))), isFalse);
    gone = gone.failed('404', transient: false).failed('404', transient: false);
    expect(gone.isBroken(start.add(const Duration(days: 2))), isTrue);

    final restored = FeedHealth.fromJson(
      jsonDecode(jsonEncode(gone.toJson())) as Map<String, dynamic>,
    );
    expect(restored.failures, 3);
    expect(restored.lastErrorTransient, isFalse);
  });

  test('a 429 is retried quietly, then the feed loads', () async {
    var calls = 0;
    final remote = RssRemoteDataSource(
      MockClient((_) async {
        calls++;
        return calls == 1
            ? http.Response('slow down', 429, headers: {'retry-after': '1'})
            : http.Response(_rss, 200);
      }),
    );
    final feed = await remote.fetch('https://x/feed');
    expect(feed.articles.single.title, 'A');
    expect(calls, 2);
  });

  test('a 404 is a real error, not a temporary one', () async {
    final remote = RssRemoteDataSource(
      MockClient((_) async => http.Response('', 404)),
    );
    await expectLater(
      remote.fetch('https://x/feed'),
      throwsA(
        isA<FeedException>()
            .having((e) => e.transient, 'transient', isFalse)
            .having((e) => e.statusCode, 'status', 404),
      ),
    );
  });

  test('per-website limit while fetching many feeds', () async {
    var active = 0, peak = 0;
    await forEachLimited<String>(
      List.filled(12, 'youtube.com'),
      (_) async {
        peak = ++active > peak ? active : peak;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        active--;
      },
      concurrency: 8,
      perKey: 3,
      keyOf: (host) => host,
    );
    expect(peak, 3);
  });

  group('Arabic', () {
    test('direction follows the letters', () {
      expect(textDirectionOf('مرحبا بكم في MyKit'), TextDirection.rtl);
      expect(textDirectionOf('Apple يعلن عن iPhone جديد'), TextDirection.rtl);
      expect(textDirectionOf('Hello world'), TextDirection.ltr);
      expect(textDirectionOf('2026 – 10'), TextDirection.ltr);
    });

    test('Windows-1256 and ISO-8859-6 feeds decode', () {
      const bytes = [227, 209, 205, 200, 199, 32, 200, 223, 227];
      final xml = [
        ...ascii.encode('<?xml version="1.0" encoding="windows-1256"?>'),
        ...bytes,
      ];
      expect(decodeTextBody(xml), endsWith('مرحبا بكم'));
      expect(
        decodeTextBody(bytes, contentType: 'text/xml; charset=windows-1256'),
        'مرحبا بكم',
      );
      expect(decodeTextBody(utf8.encode('مرحبا')), 'مرحبا');
    });
  });

  group('reading time', () {
    FeedArticle article({String content = '', String summary = ''}) =>
        FeedArticle(
          id: 'a',
          feedId: 'f',
          title: 't',
          content: content,
          summary: summary,
        );

    test('minutes and length from the feed text', () {
      expect(ReadingTime.of(article(content: 'word ' * 100)).label, '< 1 min');
      final mid = ReadingTime.of(article(content: 'word ' * 1150));
      expect((mid.minutes, mid.length), (5, ReadingLength.medium));
      expect(
        ReadingTime.of(article(content: 'word ' * 3000)).length,
        ReadingLength.long,
      );
    });

    test('a teaser-only feed says Preview; Arabic reads slower', () {
      expect(
        ReadingTime.of(article(summary: 'Short teaser text.')).label,
        'Preview',
      );
      expect(
        ReadingTime.of(article(content: 'كلمة ' * 720)).minutes,
        4, // 720 / 180 wpm
      );
    });
  });

  group('chat follow-ups', () {
    test('split from the answer', () {
      final (body, followUps) = splitFollowUps(
        'Answer here.\n\n**FOLLOW_UPS:** Who? | Why now? | What next?',
      );
      expect(body, 'Answer here.');
      expect(followUps, ['Who?', 'Why now?', 'What next?']);
      expect(splitFollowUps('No list').$2, isEmpty);
    });

    test('hidden while streaming, even half-written', () {
      expect(visibleAnswer('Text\nFOLL'), 'Text');
      expect(visibleAnswer('Text\nFOLLOW_UPS: a | b'), 'Text');
      expect(visibleAnswer('Text\nFollowing the war'), contains('Following'));
    });
  });
}
