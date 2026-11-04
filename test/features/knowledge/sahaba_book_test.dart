import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykit/core/storage/shared_preferences_provider.dart';
import 'package:mykit/features/knowledge/domain/sahaba_models.dart';
import 'package:mykit/features/knowledge/presentation/providers/sahaba_providers.dart';
import 'package:mykit/features/knowledge/presentation/screens/sahaba_screens.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<SahabaPerson> _index() =>
    SahabaPerson.parseIndex(File('assets/sahaba/index.txt').readAsStringSync());

Map<SahabaBook, List<SahabaChapter>> _person(String id) =>
    parseSahabaFile(File('assets/sahaba/$id.txt').readAsStringSync());

void main() {
  test('everyone in the index has a file with text in the books listed', () {
    final people = _index();
    expect(people.length, 156);
    for (final p in people) {
      final books = _person(p.id);
      expect(books.keys.toSet(), p.books.toSet(), reason: p.id);
      for (final b in p.books) {
        final chapters = books[b]!;
        expect(chapters.where((c) => c.hasText), isNotEmpty, reason: p.id);
        final words = chapters
            .expand((c) => c.paragraphs)
            .fold<int>(0, (n, t) => n + t.split(' ').length);
        expect(words, p.words(b), reason: '${p.id} ${b.name}');
      }
    }
  });

  test('no markup from the source files is left in the text', () {
    final markup = RegExp(r'PageV\d|ms\d|~~|%~%|^#|^###|\$');
    for (final p in _index()) {
      for (final c in _person(p.id).values.expand((c) => c)) {
        expect(markup.hasMatch(c.title), isFalse, reason: c.title);
        for (final t in c.paragraphs) {
          expect(markup.hasMatch(t), isFalse, reason: '${p.id}: $t');
        }
      }
    }
  });

  test('Umar has the long book, with the chapters on who he was', () {
    final books = _person('umar');
    final riyad = books[SahabaBook.riyad]!;
    final titles = riyad.map((c) => c.title).toList();
    for (final name in [
      'الفصل الرابع: في إسلامه',
      'ذكر زهده',
      'ذكر خوفه',
      'ذكر تواضعه',
      'ذكر فراسته',
    ]) {
      expect(titles, contains(name));
    }
    expect(
      riyad.expand((c) => c.paragraphs).fold<int>(0, (n, t) => n + t.length),
      greaterThan(200000),
    );
    expect(
      books[SahabaBook.sifat]!.map((c) => c.title),
      contains('ذكر زهده رضي الله عنه'),
    );
  });

  test('a paragraph split only by a printed page is whole again', () {
    final chapter = _person(
      'umar',
    )[SahabaBook.riyad]!.firstWhere((c) => c.title.startsWith('ذكر شفقته'));
    expect(chapter.location, startsWith('ج2، ص383'));
    expect(
      chapter.paragraphs.any(
        (p) =>
            p.startsWith('وعن عدي بن حاتم') &&
            p.contains('صدقة طيئ، حيث جئت بها'),
      ),
      isTrue,
    );
  });

  test(
    'searching ignores how the digitised text writes hamza and ta marbuta',
    () {
      expect(normalizeArabic('أسامة'), normalizeArabic('اسامه'));
    },
  );

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

    testWidgets('Umar lists both books and his chapters', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(app(const SahabaPersonScreen(id: 'umar')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      expect(find.text('مفصّل'), findsOneWidget);
      expect(find.text('مختصر'), findsOneWidget);
      expect(find.text('الفصل الأول: في نسبه أصلا وفرعا'), findsOneWidget);

      await tester.tap(find.text('مختصر'));
      await tester.pump();
      expect(find.text('ذكر سبب إسلامه'), findsOneWidget);
    });

    testWidgets('the reader shows the chapter and remembers it', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          app(
            const SahabaReaderScreen(
              id: 'umar',
              book: SahabaBook.sifat,
              index: 1,
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      final chapter = _person('umar')[SahabaBook.sifat]![1];
      expect(find.text(chapter.paragraphs.first), findsOneWidget);
      expect(find.text('الفصل التالي'), findsOneWidget);
      expect(
        prefs.getString('sahaba.last'),
        sahabaKey('umar', SahabaBook.sifat, 1),
      );
    });
  });
}
