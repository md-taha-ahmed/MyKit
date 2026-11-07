import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mykit/features/read_aloud/data/read_aloud_service.dart';
import 'package:mykit/features/read_aloud/presentation/read_aloud_popup.dart';

const _verse = 'قفا نبك من ذكرى حبيب ومنزل';
const _vowelled = 'قِفَا نَبْكِ مِنْ ذِكْرَى حَبِيبٍ وَمَنْزِلِ';

http.Response _text(String t) => http.Response.bytes(
  utf8.encode(
    jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': t},
            ],
          },
        },
      ],
    }),
  ),
  200,
);

http.Response _audio(String mime, List<int> bytes) => http.Response(
  jsonEncode({
    'candidates': [
      {
        'content': {
          'parts': [
            {
              'inlineData': {'mimeType': mime, 'data': base64.encode(bytes)},
            },
          ],
        },
      },
    ],
  }),
  200,
);

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('read_aloud'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('checks', () {
    test('tell vowelled text from plain', () {
      expect(isVowelled(_verse), isFalse);
      expect(isVowelled(_vowelled), isTrue);
    });

    test('vowels do not count as changed letters, a new letter does', () {
      expect(arabicLetters(_vowelled), arabicLetters(_verse));
      expect(arabicLetters('وَآحَرَّ'), isNot(arabicLetters('واحر')));
    });

    test('raw audio gets a playable header', () {
      final wav = pcmToWav(Uint8List.fromList([1, 2, 3, 4]), 24000);
      expect(ascii.decode(wav.sublist(0, 4)), 'RIFF');
      expect(wav.length, 48);
      expect(ByteData.sublistView(wav).getUint32(24, Endian.little), 24000);
    });
  });

  group('prepare', () {
    test('vowels then voice, and the second time uses no data', () async {
      var requests = 0;
      String? spoken;
      final client = MockClient((r) async {
        requests++;
        if (r.url.path.contains('tts')) {
          spoken = r.body;
          return _audio('audio/wav', [9, 9]);
        }
        return _text(_vowelled);
      });
      final service = ReadAloudService(client, 'k', dir);

      final first = await service.prepare(_verse);
      expect(first.text, _vowelled);
      expect(first.vowelled, isTrue);
      // Nothing but the text, or the voice reads the rest out too.
      final sent = jsonDecode(spoken!) as Map<String, dynamic>;
      final contents = sent['contents'] as List;
      expect((contents.single as Map)['parts'], [
        {'text': _vowelled},
      ]);
      expect(sent.containsKey('systemInstruction'), isFalse);
      expect(
        jsonEncode(sent['generationConfig']),
        contains('"voiceName":"Iapetus"'),
      );
      expect(requests, 2);

      final again = await service.prepare(_verse);
      expect(again.fromCache, isTrue);
      expect(again.text, _vowelled);
      expect(requests, 2);
    });

    test('reads the original if vowelling changed a letter', () async {
      final service = ReadAloudService(
        MockClient(
          (r) async => r.url.path.contains('tts')
              ? _audio('audio/wav', [1])
              : _text('قِفَا نَبْكِي مِنْ ذِكْرَى'),
        ),
        'k',
        dir,
      );
      final result = await service.prepare(_verse);
      expect(result.text, _verse);
      expect(result.vowelled, isFalse);
    });

    test('moves on when a voice model refuses or is busy', () async {
      final tried = <String>[];
      final service = ReadAloudService(
        MockClient((r) async {
          if (!r.url.path.contains('tts')) return _text(_vowelled);
          tried.add(r.url.path);
          return switch (tried.length) {
            1 => http.Response('{}', 503),
            2 => http.Response(
              jsonEncode({
                'candidates': [
                  {'finishReason': 'SAFETY'},
                ],
              }),
              200,
            ),
            _ => _audio('audio/l16; rate=24000', [1, 2]),
          };
        }),
        'k',
        dir,
      );
      final result = await service.prepare(_verse);
      expect(tried.length, 3);
      final saved = await result.audio.readAsBytes();
      expect(ascii.decode(saved.sublist(0, 4)), 'RIFF');
    });

    test('no connection is said plainly, and nothing is saved', () async {
      final service = ReadAloudService(
        MockClient((_) async => throw const SocketException('off')),
        'k',
        dir,
      );
      await expectLater(
        service.prepare('hello'),
        throwsA(
          isA<ReadAloudException>().having(
            (e) => e.message,
            'message',
            contains('لا يوجد اتصال'),
          ),
        ),
      );
      expect(await service.isCached('hello'), isFalse);
    });

    test('slow vowels are skipped, and the text is still read', () async {
      final service = ReadAloudService(
        MockClient((r) async {
          if (r.url.path.contains('tts')) return _audio('audio/wav', [1]);
          await Future<void>.delayed(const Duration(seconds: 5));
          return _text(_vowelled);
        }),
        'k',
        dir,
        vowelBudget: const Duration(milliseconds: 50),
      );
      final result = await service.prepare(_verse);
      expect(result.text, _verse);
      expect(result.vowelled, isFalse);
    });

    test('a voice model that hangs does not fail the reading', () async {
      var voices = 0;
      final service = ReadAloudService(
        MockClient((r) async {
          if (!r.url.path.contains('tts')) return _text(_vowelled);
          if (++voices == 1) {
            await Future<void>.delayed(const Duration(seconds: 5));
          }
          return _audio('audio/wav', [1]);
        }),
        'k',
        dir,
        voiceTimeout: const Duration(milliseconds: 50),
      );
      await service.prepare(_verse);
      expect(voices, 2);
    });

    test('when everything is slow it says slow, not offline', () async {
      final service = ReadAloudService(
        MockClient((_) async {
          await Future<void>.delayed(const Duration(seconds: 5));
          return _audio('audio/wav', [1]);
        }),
        'k',
        dir,
        voiceTimeout: Duration.zero,
      );
      await expectLater(
        service.prepare('hello'),
        throwsA(
          isA<ReadAloudException>().having(
            (e) => e.message,
            'message',
            contains('وقتاً طويلاً'),
          ),
        ),
      );
    });

    test('says what it is doing while you wait', () async {
      final stages = <ReadAloudStage>[];
      final service = ReadAloudService(
        MockClient(
          (r) async => r.url.path.contains('tts')
              ? _audio('audio/wav', [1])
              : _text(_vowelled),
        ),
        'k',
        dir,
      );
      await service.prepare(_verse, onStage: stages.add);
      expect(stages, [ReadAloudStage.vowels, ReadAloudStage.voice]);
    });

    test('no key asks for one', () async {
      final service = ReadAloudService(
        MockClient((_) async => http.Response('', 500)),
        null,
        dir,
      );
      await expectLater(
        service.prepare(_verse),
        throwsA(isA<ReadAloudException>()),
      );
    });

    test('text that is vowelled already is not sent for vowelling', () async {
      final paths = <String>[];
      final service = ReadAloudService(
        MockClient((r) async {
          paths.add(r.url.path);
          return _audio('audio/wav', [1]);
        }),
        'k',
        dir,
      );
      await service.prepare(_vowelled);
      expect(paths.single, contains('tts'));
    });
  });

  group('popup', () {
    Widget popup(String text, {void Function()? closed}) => MaterialApp(
      home: ReadAloudPopup(
        text: text,
        onClose: () async => closed?.call(),
        service: () async => ReadAloudService(
          MockClient((_) async => http.Response('', 500)),
          'k',
          dir,
        ),
      ),
    );

    testWidgets('a long selection says what it costs before using data', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(popup('ب' * 800));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      expect(find.textContaining('12 ميجابايت'), findsOneWidget);
      expect(find.text('متابعة'), findsOneWidget);
    });

    testWidgets('too long and empty selections explain themselves', (
      tester,
    ) async {
      await tester.pumpWidget(popup('ب' * (readAloudMaxChars + 1)));
      expect(find.textContaining('طويل جداً'), findsOneWidget);
      await tester.pumpWidget(Container());
      await tester.pumpWidget(popup('  '));
      expect(find.textContaining('لم يصل'), findsOneWidget);
    });

    testWidgets('tapping outside closes it', (tester) async {
      var closed = false;
      await tester.pumpWidget(popup('  ', closed: () => closed = true));
      await tester.tapAt(const Offset(20, 20));
      expect(closed, isTrue);
    });
  });
}
