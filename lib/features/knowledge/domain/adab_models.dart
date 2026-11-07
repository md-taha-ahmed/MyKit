import 'knowledge_models.dart';

const _openIti = 'https://github.com/OpenITI';

/// The classical literature bundled so it works with no connection (see
/// tool/build_adab_books.py). Each is one OpenITI text, pinned to a commit.
enum AdabBook {
  uyun(
    title: 'عيون الأخبار',
    author: 'ابن قتيبة (ت 276هـ)',
    about:
        'أخبار وحكم وأشعار مرتبة في عشرة كتب: السلطان، والحرب، والعلم، والزهد…',
    edition: 'دار الكتب العلمية، بيروت، 1418هـ',
    url:
        '$_openIti/0300AH/blob/01a1544130e0236850ef2698923ad01575c5bd7c/data/0276IbnQutaybaDinawari/0276IbnQutaybaDinawari.CuyunAkhbar/0276IbnQutaybaDinawari.CuyunAkhbar.Shamela0023790-ara1.completed',
    readOnline: 'https://shamela.ws/book/23790',
  ),
  shir(
    title: 'الشعر والشعراء',
    author: 'ابن قتيبة (ت 276هـ)',
    about:
        'أخبار أكثر من مئتي شاعر ومختارات من شعرهم، من امرئ القيس إلى أبي نواس',
    edition: 'تحقيق أحمد محمد شاكر، دار الحديث، القاهرة، 1423هـ',
    url:
        '$_openIti/0300AH/blob/01a1544130e0236850ef2698923ad01575c5bd7c/data/0276IbnQutaybaDinawari/0276IbnQutaybaDinawari.ShicrWaShucara/0276IbnQutaybaDinawari.ShicrWaShucara.Shamela0023785-ara1.mARkdown',
    readOnline: 'https://shamela.ws/book/23785',
  ),
  bukhala(
    title: 'البخلاء',
    author: 'الجاحظ (ت 255هـ)',
    about: 'قصص طريفة عن البخلاء وحججهم، وأقصرها قصة واحدة في دقيقة',
    edition: 'دار ومكتبة الهلال، بيروت، ط2، 1419هـ',
    url:
        '$_openIti/0275AH/blob/44e1c36738a2bf5c14dafa232a6ae1891e6171cd/data/0255Jahiz/0255Jahiz.Bukhala/0255Jahiz.Bukhala.Shamela0010501-ara1.mARkdown',
    readOnline: 'https://shamela.ws/book/10501',
  ),
  kalila(
    title: 'كليلة ودمنة',
    author: 'ابن المقفع (ت 142هـ)',
    about: 'حكمة السياسة والحياة على ألسنة الحيوان',
    edition: 'المطبعة الأميرية ببولاق، القاهرة، ط17، 1355هـ',
    url:
        '$_openIti/0150AH/blob/f9a52b5bbc3a65673fc73fb32331e7f33811c480/data/0139IbnMuqaffac/0139IbnMuqaffac.KalilaWaDimna/0139IbnMuqaffac.KalilaWaDimna.Shamela0026537-ara1',
    readOnline: 'https://shamela.ws/book/26537',
  ),
  kamil(
    title: 'الكامل في اللغة والأدب',
    author: 'المبرد (ت 285هـ)',
    about: 'خطب وأشعار وأخبار مع شرح لغتها، وفيه أخبار الخوارج',
    edition:
        'تحقيق محمد أبو الفضل إبراهيم، دار الفكر العربي، القاهرة، ط3، 1417هـ',
    url:
        '$_openIti/0300AH/blob/01a1544130e0236850ef2698923ad01575c5bd7c/data/0285IbnYazidMubarrad/0285IbnYazidMubarrad.KamilFiLugha/0285IbnYazidMubarrad.KamilFiLugha.Shamela0008505-ara1.mARkdown',
    readOnline: 'https://shamela.ws/book/8505',
  ),
  bayan(
    title: 'البيان والتبيين',
    author: 'الجاحظ (ت 255هـ)',
    about: 'البلاغة والخطابة عند العرب، وأخبار الخطباء والبلغاء',
    edition: 'دار ومكتبة الهلال، بيروت، 1423هـ',
    url:
        '$_openIti/0275AH/blob/44e1c36738a2bf5c14dafa232a6ae1891e6171cd/data/0255Jahiz/0255Jahiz.BayanWaTabyin/0255Jahiz.BayanWaTabyin.Shamela0010614-ara1.completed',
    readOnline: 'https://shamela.ws/book/10614',
  ),
  iqd(
    title: 'العقد الفريد',
    author: 'ابن عبد ربه (ت 328هـ)',
    about:
        'موسوعة الأدب: خمسة وعشرون كتاباً في الحرب والعلم والأمثال والأنساب والشعر',
    edition: 'دار الكتب العلمية، بيروت، ط1، 1404هـ',
    url:
        '$_openIti/0350AH/blob/3f52b87dc367365000b32f815a3d0077451c46f4/data/0328IbnCabdRabbih/0328IbnCabdRabbih.CiqdFarid/0328IbnCabdRabbih.CiqdFarid.Shamela0023789-ara1.completed',
    readOnline: 'https://shamela.ws/book/23789',
  );

  const AdabBook({
    required this.title,
    required this.author,
    required this.about,
    required this.edition,
    required this.url,
    required this.readOnline,
  });

  final String title;
  final String author;
  final String about;
  final String edition;
  final String url;
  final String readOnline;
}

/// One row of assets/adab/index.txt: `book|words|chapters`.
class AdabBookStats {
  const AdabBookStats({required this.words, required this.chapters});

  final int words;
  final int chapters;

  static Map<AdabBook, AdabBookStats> parseIndex(String text) {
    final stats = <AdabBook, AdabBookStats>{};
    for (final line in text.split('\n')) {
      if (line.trim().isEmpty) continue;
      final f = line.split('|');
      stats[AdabBook.values.byName(f[0])] = AdabBookStats(
        words: int.parse(f[1]),
        chapters: int.parse(f[2]),
      );
    }
    return stats;
  }
}

/// A chapter of a book. One with no [blocks] only heads the ones under it.
class AdabChapter {
  const AdabChapter({
    required this.level,
    required this.title,
    required this.location,
    required this.blocks,
  });

  /// 1 for a main chapter, 2 for one inside it.
  final int level;
  final String title;

  /// "ج2، ص383–392" in the printed edition.
  final String? location;
  final List<LessonBlock> blocks;

  bool get hasText => blocks.any((b) => !b.heading);
}

/// `@ch level title`, an optional `@loc`, `@h subheading`, and a line for each
/// paragraph. Lines of the same poem become one block, so they read as a poem.
List<AdabChapter> parseAdabFile(String text) {
  final chapters = <AdabChapter>[];
  int? level;
  String? title;
  String? location;
  var blocks = <LessonBlock>[];
  var inVerse = false;

  void finish() {
    if (title != null) {
      chapters.add(
        AdabChapter(
          level: level!,
          title: title!,
          location: location,
          blocks: blocks,
        ),
      );
    }
    title = null;
    location = null;
    blocks = [];
    inVerse = false;
  }

  for (final line in text.split('\n')) {
    if (line.isEmpty) continue;
    if (line.startsWith('@ch ')) {
      finish();
      level = int.parse(line.substring(4, 5));
      title = line.substring(6);
    } else if (line.startsWith('@loc ')) {
      location = line.substring(5);
    } else if (line.startsWith('@h ')) {
      blocks.add(LessonBlock(line.substring(3), heading: true));
      inVerse = false;
    } else {
      final verse = line.contains(' … ');
      if (verse && inVerse) {
        blocks[blocks.length - 1] = LessonBlock('${blocks.last.text}\n$line');
      } else {
        blocks.add(LessonBlock(line));
      }
      inVerse = verse;
    }
  }
  finish();
  return chapters;
}

extension AdabLesson on AdabChapter {
  /// As a lesson, so saving, copying and the helper work like everywhere else.
  Lesson toLesson(AdabBook book, int index) => Lesson(
    id: 'adab@${book.name}/$index',
    trackId: 'adab-book',
    title: title,
    blocks: blocks,
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
