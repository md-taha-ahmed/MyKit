import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mykit/core/storage/shared_preferences_provider.dart';
import 'package:mykit/features/movies/data/datasources/open_subtitles_client.dart';
import 'package:mykit/features/movies/presentation/providers/movies_providers.dart';
import 'package:mykit/features/movies/presentation/widgets/subtitle_search_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _json(Object body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: {'content-type': 'application/json'},
);

const _arabic = {
  'id': '1',
  'url': 'https://subs.example/ar.srt',
  'lang': 'ara',
  'subtitleFileName': 'Frieren.S01E05.ar.srt',
};
const _english = {
  'id': '2',
  'url': 'https://subs.example/en.srt',
  'lang': 'eng',
  'subtitleFileName': 'Frieren.S01E05.en.srt',
};

void main() {
  test('reads the IMDb id, season and episode from a Stremio id', () {
    final episode = parseImdbVideoId('tt22248376:1:5')!;
    expect(episode.imdbId, 'tt22248376');
    expect(episode.isSeries, isTrue);
    expect(episode.season, 1);
    expect(episode.episode, 5);
    expect(parseImdbVideoId('tt0111161')!.isSeries, isFalse);
    expect(parseImdbVideoId('kitsu:123:4'), isNull);
    expect(parseImdbVideoId('source/anime/ep4'), isNull);
  });

  test('finds the episode number in an anime label', () {
    expect(episodeNumberFromLabel('Episode 12'), 12);
    expect(episodeNumberFromLabel('الحلقة 7'), 7);
    expect(episodeNumberFromLabel('Special'), isNull);
    expect(episodeNumberFromLabel(null), isNull);
  });

  test('searches shows and films, keeping only IMDb titles', () async {
    final urls = <String>[];
    final client = OpenSubtitlesClient(
      MockClient((r) async {
        urls.add(r.url.toString());
        return _json({
          'metas': r.url.path.contains('/series/')
              ? [
                  {'imdb_id': 'tt1', 'name': 'Show', 'releaseInfo': '2023'},
                  {'id': 'kitsu:9', 'name': 'Not IMDb'},
                ]
              : [
                  {'id': 'tt2', 'name': 'Film'},
                ],
        });
      }),
    );
    final found = await client.searchTitles('a show', seriesFirst: false);
    expect(found.map((t) => t.name), ['Film', 'Show']);
    expect(found.last.isSeries, isTrue);
    expect(found.last.year, '2023');
    expect(urls, hasLength(2));
    expect(urls.first, contains('search=a%20show.json'));
  });

  test('asks for the right episode and keeps the file name', () async {
    late Uri asked;
    final client = OpenSubtitlesClient(
      MockClient((r) async {
        asked = r.url;
        return _json({
          'subtitles': [_arabic],
        });
      }),
    );
    final found = await client.subtitles(
      const SubtitleTitle(imdbId: 'tt1', name: 'Show', isSeries: true),
      season: 2,
      episode: 5,
    );
    expect(asked.path, '/subtitles/series/tt1:2:5.json');
    expect(found.single.fileName, 'Frieren.S01E05.ar.srt');
    expect(found.single.addonName, 'OpenSubtitles');

    await client.subtitles(
      const SubtitleTitle(imdbId: 'tt2', name: 'Film', isSeries: false),
    );
    expect(asked.path, '/subtitles/movie/tt2.json');
  });

  group('search sheet', () {
    late SharedPreferences prefs;
    late List<String> requests;

    setUp(() async {
      SharedPreferences.setMockInitialValues({'movies.subtitleLang': 'ara'});
      prefs = await SharedPreferences.getInstance();
      requests = [];
    });

    Future<ValueNotifier<Object?>> open(
      WidgetTester tester,
      SubtitleSearchRequest request, {
      bool offline = false,
    }) async {
      final picked = ValueNotifier<Object?>('nothing');
      final client = OpenSubtitlesClient(
        MockClient((r) async {
          requests.add(r.url.path);
          if (offline) throw http.ClientException('offline');
          if (r.url.path.startsWith('/catalog/series')) {
            return _json({
              'metas': [
                {'imdb_id': 'tt1', 'name': 'Frieren', 'releaseInfo': '2023'},
              ],
            });
          }
          if (r.url.path.startsWith('/catalog')) return _json({'metas': []});
          return _json({
            'subtitles': [_arabic, _english],
          });
        }),
      );
      await tester.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            openSubtitlesClientProvider.overrideWithValue(client),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async => picked.value =
                    await showSubtitleSearchSheet(context, request),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      return picked;
    }

    const anime = SubtitleSearchRequest(
      metaId: 'source/frieren',
      videoId: 'source/frieren/5',
      name: 'Frieren',
      seriesLike: true,
      episodeLabel: 'Episode 5',
    );

    testWidgets('anime: pick the show, then choose a subtitle', (tester) async {
      final picked = await open(tester, anime);
      await tester.tap(find.widgetWithText(ListTile, 'Frieren'));
      await tester.pumpAndSettle();

      expect(requests.last, '/subtitles/series/tt1:1:5.json');
      // The language you read is chosen, and the others wait behind a chip.
      expect(find.text('Frieren.S01E05.ar.srt'), findsOneWidget);
      expect(find.text('Frieren.S01E05.en.srt'), findsNothing);

      await tester.tap(find.text('Frieren.S01E05.ar.srt'));
      await tester.pumpAndSettle();
      expect((picked.value as dynamic).url, 'https://subs.example/ar.srt');
    });

    testWidgets('the next episode does not ask for the show again', (
      tester,
    ) async {
      await open(tester, anime);
      await tester.tap(find.widgetWithText(ListTile, 'Frieren'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Frieren.S01E05.ar.srt'));
      await tester.pumpAndSettle();
      requests.clear();

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(requests, ['/subtitles/series/tt1:1:5.json']);
    });

    testWidgets('Stremio: goes straight to the episode, no title search', (
      tester,
    ) async {
      await open(
        tester,
        const SubtitleSearchRequest(
          metaId: 'tt22248376',
          videoId: 'tt22248376:1:5',
          name: 'Frieren',
          seriesLike: true,
        ),
      );
      expect(requests, ['/subtitles/series/tt22248376:1:5.json']);
      expect(find.text('Frieren.S01E05.ar.srt'), findsOneWidget);
    });

    testWidgets('no connection says so', (tester) async {
      await open(tester, anime, offline: true);
      expect(find.textContaining('OpenSubtitles'), findsWidgets);
      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(
        find.text(
          'Could not reach OpenSubtitles. Check your connection and try again.',
        ),
        findsOneWidget,
      );
    });
  });
}
