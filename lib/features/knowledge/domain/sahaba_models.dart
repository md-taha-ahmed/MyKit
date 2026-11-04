import 'knowledge_models.dart';

/// The two old books the Sahabah section is made of, bundled so it works with
/// no connection (see tool/build_sahaba_book.py).
enum SahabaBook {
  riyad(
    label: 'مفصّل',
    title: 'الرياض النضرة في مناقب العشرة',
    author: 'المحب الطبري (ت 694هـ)',
    edition: 'دار الكتب العلمية، ط2',
    url:
        'https://github.com/OpenITI/0700AH/blob/3d8ff4e7b035aaa4ca5dda52c7322645f3401dcf/data/0694MuhibbDinTabari/0694MuhibbDinTabari.RiyadNadira/0694MuhibbDinTabari.RiyadNadira.Shamela0008657-ara1.completed',
    readOnline: 'https://shamela.ws/book/8657',
  ),
  sifat(
    label: 'مختصر',
    title: 'صفة الصفوة',
    author: 'ابن الجوزي (ت 597هـ)',
    edition: 'تحقيق أحمد بن علي، دار الحديث، القاهرة، 1421هـ/2000م',
    url:
        'https://github.com/OpenITI/0600AH/blob/ea4bdc6517a49d07106f223aa0869aa7c21b9589/data/0597IbnJawzi/0597IbnJawzi.SifatSafwa/0597IbnJawzi.SifatSafwa.Shamela0012031-ara1.mARkdown',
    readOnline: 'https://shamela.ws/book/12031',
  );

  const SahabaBook({
    required this.label,
    required this.title,
    required this.author,
    required this.edition,
    required this.url,
    required this.readOnline,
  });

  final String label;
  final String title;
  final String author;
  final String edition;
  final String url;
  final String readOnline;
}

/// A companion, as listed in assets/sahaba/index.txt.
class SahabaPerson {
  const SahabaPerson({
    required this.id,
    required this.name,
    required this.group,
    required this.riyadWords,
    required this.sifatWords,
  });

  final String id;
  final String name;
  final String group;
  final int riyadWords;
  final int sifatWords;

  int words(SahabaBook book) =>
      book == SahabaBook.riyad ? riyadWords : sifatWords;

  List<SahabaBook> get books => [
    for (final b in SahabaBook.values)
      if (words(b) > 0) b,
  ];

  /// `id|name|group|riyadWords|sifatWords` lines.
  static List<SahabaPerson> parseIndex(String text) {
    final people = <SahabaPerson>[];
    for (final line in text.split('\n')) {
      if (line.trim().isEmpty) continue;
      final f = line.split('|');
      people.add(
        SahabaPerson(
          id: f[0],
          name: f[1],
          group: f[2],
          riyadWords: int.parse(f[3]),
          sifatWords: int.parse(f[4]),
        ),
      );
    }
    return people;
  }
}

/// A chapter of one book about one person. A chapter with no [paragraphs]
/// only heads the ones under it.
class SahabaChapter {
  const SahabaChapter({
    required this.level,
    required this.title,
    required this.location,
    required this.paragraphs,
  });

  /// 1 for a main chapter, 2 for one inside it.
  final int level;
  final String title;

  /// "ج2، ص383–392" in the printed edition.
  final String? location;
  final List<String> paragraphs;

  bool get hasText => paragraphs.isNotEmpty;
}

/// A person's file: `@book`, then `@ch level title`, an optional `@loc`, and
/// a line for each paragraph.
Map<SahabaBook, List<SahabaChapter>> parseSahabaFile(String text) {
  final books = <SahabaBook, List<SahabaChapter>>{};
  List<SahabaChapter>? chapters;
  int? level;
  String? title;
  String? location;
  var paragraphs = <String>[];

  void finish() {
    if (title != null) {
      chapters!.add(
        SahabaChapter(
          level: level!,
          title: title!,
          location: location,
          paragraphs: paragraphs,
        ),
      );
    }
    title = null;
    location = null;
    paragraphs = [];
  }

  for (final line in text.split('\n')) {
    if (line.isEmpty) continue;
    if (line.startsWith('@book ')) {
      finish();
      chapters = books[SahabaBook.values.byName(line.substring(6))] = [];
    } else if (line.startsWith('@ch ')) {
      finish();
      level = int.parse(line.substring(4, 5));
      title = line.substring(6);
    } else if (line.startsWith('@loc ')) {
      location = line.substring(5);
    } else {
      paragraphs.add(line);
    }
  }
  finish();
  return books;
}

extension SahabaLesson on SahabaChapter {
  /// As a lesson, so saving, copying and the helper work like everywhere else.
  Lesson toLesson(SahabaPerson person, SahabaBook book, int index) => Lesson(
    id: 'sahaba@${person.id}/${book.name}/$index',
    trackId: 'sahaba-book',
    title: '${person.name}: $title',
    blocks: [for (final p in paragraphs) LessonBlock(p)],
    reference: LessonReference(
      source: book.title,
      author: book.author,
      edition: book.edition,
      location: location,
      url: book.url,
      checkUrl: book.readOnline,
    ),
  );
}

/// "نحو 25 د" / "نحو 4 س", at a slow pace because the language is old.
String sahabaReadingTime(int words) {
  final minutes = (words / 170).ceil();
  if (minutes < 60) return 'نحو $minutes د';
  return 'نحو ${(minutes / 60).round()} س';
}

/// So "إسلام" finds "اسلام": the digitised text is loose about these letters.
String normalizeArabic(String text) => text
    .replaceAll(RegExp('[أإآ]'), 'ا')
    .replaceAll('ة', 'ه')
    .replaceAll('ى', 'ي')
    .replaceAll(RegExp('[ً-ْ]'), '');
