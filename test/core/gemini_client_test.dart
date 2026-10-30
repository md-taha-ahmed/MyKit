import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mykit/core/ai/gemini_client.dart';
import 'package:mykit/features/rss/data/datasources/article_text_source.dart';

http.Response _json(int code, Object body) => http.Response(
  jsonEncode(body),
  code,
  headers: {'content-type': 'application/json'},
);

void main() {
  test(
    'sends key, system and history; returns the text (no thoughts)',
    () async {
      late http.Request seen;
      final client = MockClient((req) async {
        seen = req;
        return _json(200, {
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'hidden', 'thought': true},
                  {'text': 'Answer'},
                ],
              },
            },
          ],
        });
      });
      final text = await GeminiClient(
        client,
        'k',
      ).generate(system: 'sys', messages: [(fromUser: true, text: 'hi')]);
      expect(text, 'Answer');
      expect(seen.headers['x-goog-api-key'], 'k');
      expect(seen.url.path, contains(GeminiClient.models.first));
      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(body['systemInstruction']['parts'][0]['text'], 'sys');
      expect(body['contents'][0]['role'], 'user');
    },
  );

  test('falls back to the next model when one is busy', () async {
    final calls = <String>[];
    final client = MockClient((req) async {
      calls.add(req.url.path);
      if (calls.length == 1) {
        return _json(503, {
          'error': {'code': 503, 'message': 'high demand'},
        });
      }
      return _json(200, {
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'ok'},
              ],
            },
          },
        ],
      });
    });
    expect(
      await GeminiClient(
        client,
        'k',
      ).generate(messages: [(fromUser: true, text: 'q')]),
      'ok',
    );
    expect(calls[1], contains(GeminiClient.models[1]));
  });

  test('friendly errors: no key, rejected key, quota', () async {
    expect(
      () => GeminiClient(
        MockClient((_) async => _json(200, {})),
        null,
      ).generate(messages: [(fromUser: true, text: 'q')]),
      throwsA(isA<AiException>()),
    );
    final rejected = GeminiClient(
      MockClient(
        (_) async => _json(400, {
          'error': {'message': 'API key not valid'},
        }),
      ),
      'bad',
    );
    await expectLater(
      rejected.generate(messages: [(fromUser: true, text: 'q')]),
      throwsA(predicate((e) => e.toString().contains('key was rejected'))),
    );
    final quota = GeminiClient(
      MockClient(
        (_) async => _json(429, {
          'error': {'message': 'quota'},
        }),
      ),
      'k',
    );
    await expectLater(
      quota.generate(messages: [(fromUser: true, text: 'q')]),
      throwsA(predicate((e) => e.toString().contains('quota'))),
    );
  });

  test(
    'streams the answer with its sources; drops search if refused',
    () async {
      final bodies = <Map<String, dynamic>>[];
      String sse(Map<String, Object> chunk) => 'data: ${jsonEncode(chunk)}\n\n';
      final client = MockClient.streaming((req, body) async {
        final json =
            jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
        bodies.add(json);
        if (json.containsKey('tools')) {
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                jsonEncode({
                  'error': {'message': 'Search grounding is not supported.'},
                }),
              ),
            ),
            400,
          );
        }
        expect(req.url.query, 'alt=sse');
        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode(
              sse({
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'Hel'},
                      ],
                    },
                  },
                ],
              }),
            ),
            utf8.encode(
              sse({
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'lo'},
                      ],
                    },
                    'groundingMetadata': {
                      'groundingChunks': [
                        {
                          'web': {
                            'uri': 'https://bbc.com/x',
                            'title': 'bbc.com',
                          },
                        },
                      ],
                    },
                  },
                ],
              }),
            ),
          ]),
          200,
        );
      });
      final replies = await GeminiClient(client, 'k')
          .streamReply(messages: [(fromUser: true, text: 'q')], webSearch: true)
          .toList();
      expect(replies.map((r) => r.text), containsAllInOrder(['Hel', 'Hello']));
      expect(replies.last.sources.single.url, 'https://bbc.com/x');
      expect(bodies.length, 2); // retried without the search tool
      expect(bodies.last.containsKey('tools'), isFalse);
    },
  );

  // Last: it leaves search switched off for the rest of the run.
  test(
    'no search quota (429): answers without search, then skips it',
    () async {
      final withTools = <bool>[];
      final client = MockClient((req) async {
        final json = jsonDecode(req.body) as Map<String, dynamic>;
        withTools.add(json.containsKey('tools'));
        if (json.containsKey('tools')) {
          return _json(429, {
            'error': {'message': 'quota'},
          });
        }
        return _json(200, {
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'ok'},
                ],
              },
            },
          ],
        });
      });
      final gemini = GeminiClient(client, 'k');
      final first = await gemini.reply(
        messages: [(fromUser: true, text: 'q')],
        webSearch: true,
      );
      expect(first.text, 'ok');
      expect(withTools, [true, false]); // same model, retried without search
      await gemini.reply(
        messages: [(fromUser: true, text: 'q')],
        webSearch: true,
      );
      expect(withTools.last, isFalse);
      expect(withTools.length, 3); // didn't try search again
      expect(GeminiClient.searchAvailable, isFalse);
    },
  );

  test('extracts readable article text', () {
    final para = 'This is a long enough paragraph of article text. ' * 3;
    final html =
        '<html><head><script>var x=1;</script></head><body>'
        '<nav><p>${'Menu link text that is long enough here ' * 2}</p></nav>'
        '<article><h1>Title</h1><p>$para</p><p>Short</p>'
        '<p>$para &amp; more</p><p>$para</p></article></body></html>';
    final text = ArticleTextSource.extract(html)!;
    expect(text, startsWith('Title'));
    expect(text, contains('& more'));
    expect(text, isNot(contains('Menu link')));
    expect(text, isNot(contains('var x')));
    expect(text, isNot(contains('Short')));
  });
}
