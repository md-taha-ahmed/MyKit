import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykit/core/storage/shared_preferences_provider.dart';
import 'package:mykit/features/knowledge/domain/adab_models.dart';
import 'package:mykit/features/knowledge/presentation/screens/adab_screens.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<AdabChapter> _book(AdabBook b) =>
    parseAdabFile(File('assets/adab/${b.name}.txt').readAsStringSync());

void main() {
  test('the index matches every book', () {
    final stats = AdabBookStats.parseIndex(
      File('assets/adab/index.txt').readAsStringSync(),
    );
    expect(stats.keys.toSet(), AdabBook.values.toSet());
    for (final book in AdabBook.values) {
      final readable = _book(book).where((c) => c.hasText).length;
      expect(readable, stats[book]!.chapters, reason: book.name);
    }
  });

  test('no markup from the source files is left in the text', () {
    final markup = RegExp(
      r'PageV\d|\bms\d|~~|%~%|^#|\$|«\s*\d+\s*»|\[\d+\]|</?[a-z]|PARATEXT|EDITOR',
    );
    for (final book in AdabBook.values) {
      for (final c in _book(book)) {
        expect(markup.hasMatch(c.title), isFalse, reason: c.title);
        for (final b in c.blocks) {
          expect(markup.hasMatch(b.text), isFalse, reason: b.text);
        }
      }
    }
  });

  test('a poem is one block, each verse on its own line', () {
    final chapter = _book(AdabBook.uyun).firstWhere(
      (c) => c.blocks.any((b) => b.text.startsWith('خل جنبيك لرام')),
    );
    final poem = chapter.blocks.firstWhere(
      (b) => b.text.startsWith('خل جنبيك لرام'),
    );
    expect(poem.text.split('\n'), [
      'خل جنبيك لرام … وامض عنه بسلام',
      'مت بداء الصمت خير … لك من داء الكلام',
      'إنما السالم من أل … جم فاه بلجام',
    ]);
  });

  test('the books open on what they should', () {
    expect(_book(AdabBook.kalila).first.title, 'باب مقدمة الكتاب');
    final poets = _book(AdabBook.shir).map((c) => c.title);
    expect(poets, containsAll(['امرؤ القيس بن حجر', 'أبو نواس']));
  });

  test('saving a chapter keeps the book as its reference', () {
    final lesson = _book(AdabBook.bukhala).first.toLesson(AdabBook.bukhala, 0);
    expect(lesson.id, 'adab@bukhala/0');
    expect(lesson.reference.source, 'البخلاء');
    expect(lesson.reference.checkUrl, 'https://shamela.ws/book/10501');
    expect(lesson.reference.location, isNotNull);
  });

  group('screens', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    Widget app(Widget child) => ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(home: child),
    );

    testWidgets('the home screen lists the books', (tester) async {
      await tester.pumpWidget(app(const AdabHomeScreen()));
      await tester.pump();
      expect(find.text('عيون الأخبار'), findsOneWidget);
      expect(find.text('البخلاء'), findsOneWidget);
    });

    testWidgets('searching a book finds a chapter by its title', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          app(const AdabBookScreen(book: AdabBook.kalila)),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      expect(find.text('باب مقدمة الكتاب'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'البوم');
      await tester.pump();
      expect(find.text('باب البوم والغربان'), findsOneWidget);
      expect(find.text('باب مقدمة الكتاب'), findsNothing);
    });

    testWidgets('the reader shows the chapter and remembers it', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          app(const AdabReaderScreen(book: AdabBook.kalila, index: 1)),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      final chapter = _book(AdabBook.kalila)[1];
      expect(find.text(chapter.blocks.first.text), findsOneWidget);
      expect(find.text('الفصل التالي'), findsOneWidget);
      expect(prefs.getString('adab.last'), 'kalila/1');
    });
  });
}
