import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mykit/features/knowledge/data/openiti_parser.dart';
import 'package:mykit/features/knowledge/domain/knowledge_models.dart';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

const _sample = '''######OpenITI#
#META# 020.BookTITLE	:: كتاب
#META#Header#End#

### | فصل ذكر نسبه
# الحمد لله وسلام على عباده ms12 الذين اصطفى، حمدا كثيرا
~~طيبا مباركا فيه.
# وقد أحببت أن أعلق تذكرة PageV01P080
~~في ذلك.
### | فصل ولادته
# ولد رسول الله صلى الله عليه وسلم عام الفيل.
# PageV01P081
### | 3 - 
# عن أبي هريرة قال: قال رسول الله: ((لا يقبل الله صلاة أحدكم))
''';

void main() {
  test('reads paragraphs, strips markup and keeps the text', () {
    final p = OpenItiParser.parse(
      _bytes(_sample),
      atFileEnd: true,
      minChars: 50,
      maxChars: 5000,
    );
    expect(p.blocks.first.heading, isTrue);
    expect(p.blocks.first.text, 'فصل ذكر نسبه');
    expect(
      p.blocks[1].text,
      'الحمد لله وسلام على عباده الذين اصطفى، حمدا كثيرا طيبا مباركا فيه.',
    );
    expect(p.blocks[2].text, 'وقد أحببت أن أعلق تذكرة في ذلك.');
    // Stops at the next chapter once there's enough text.
    expect(p.blocks.length, 3);
    expect(p.lastHeading, 'فصل ذكر نسبه');
    // "في ذلك." comes after the end of page 80.
    expect(OpenItiParser.location(p.pages, volumes: false), 'ص80–81');
    expect(p.reachedEnd, isFalse);
    expect(p.cutShort, isFalse);

    // The next passage starts exactly at "### | فصل ولادته".
    final rest = _bytes(_sample).sublist(p.consumed);
    expect(utf8.decode(rest), startsWith('### | فصل ولادته'));
    final q = OpenItiParser.parse(
      rest,
      atFileEnd: true,
      minChars: 5000,
      maxChars: 9000,
    );
    expect(q.blocks.map((b) => b.text), [
      'فصل ولادته',
      'ولد رسول الله صلى الله عليه وسلم عام الفيل.',
      'الحديث رقم 3',
      'عن أبي هريرة قال: قال رسول الله: ((لا يقبل الله صلاة أحدكم))',
    ]);
    // Hadith numbers aren't chapters.
    expect(q.lastHeading, 'فصل ولادته');
    expect(q.reachedEnd, isTrue);
  });

  test('a chunk that ends mid-passage asks for more', () {
    final cut = _sample.substring(0, _sample.indexOf('طيبا'));
    final p = OpenItiParser.parse(
      _bytes(cut),
      atFileEnd: false,
      minChars: 5000,
      maxChars: 9000,
    );
    expect(p.cutShort, isTrue);
  });

  test('page ranges across volumes', () {
    expect(
      OpenItiParser.location([
        (volume: 9, page: 412),
        (volume: 9, page: 413),
      ], volumes: true),
      'ج9، ص412–413',
    );
    expect(
      OpenItiParser.location([
        (volume: 9, page: 520),
        (volume: 10, page: 1),
      ], volumes: true),
      'ج9، ص520 – ج10، ص1',
    );
  });

  test('lessons and settings survive JSON', () {
    const lesson = Lesson(
      id: 'seerah@0',
      trackId: 'seerah',
      title: 'فصل',
      day: '2026-10-31',
      blocks: [LessonBlock('فصل', heading: true), LessonBlock('نص')],
      reference: LessonReference(
        source: 'الفصول في السيرة',
        url: 'https://example.org',
        location: 'ص80',
      ),
    );
    final back = Lesson.fromJson(
      jsonDecode(jsonEncode(lesson.toJson())) as Map<String, dynamic>,
    );
    expect(back.plainText, lesson.plainText);
    expect(back.blocks.first.heading, isTrue);
    expect(back.reference.location, 'ص80');
    expect(back.day, '2026-10-31');

    final s = const KnowledgeSettings().copyWith(
      minutes: 600,
      schedule: {1: 'aqeedah'},
    );
    final s2 = KnowledgeSettings.fromJson(
      jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>,
    );
    expect(s2.minutes, 600);
    expect(s2.schedule, {1: 'aqeedah'});
  });
}
