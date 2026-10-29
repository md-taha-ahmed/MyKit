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
