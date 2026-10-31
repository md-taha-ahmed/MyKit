import '../domain/knowledge_models.dart';

/// What MyKit teaches from. Every text is the original book (OpenITI, pinned
/// to a commit) or an Arabic Wikipedia article for world history; the AI
/// only explains these, it is never the source.
abstract final class KnowledgeCatalog {
  static const _ibnKathir = 'ابن كثير (ت 774هـ)';

  static const seerah = KnowledgeTrack(
    id: 'seerah',
    topic: 'السيرة النبوية',
    title: 'الفصول في السيرة',
    description: 'سيرة النبي ﷺ وغزواته مختصرةً، لابن كثير',
    kind: TrackKind.book,
    book: BookSource(
      repo: '0775AH',
      commit: '61b0c7891699554aeff8dffdb8b1a2a59d2d22ab',
      path:
          'data/0774IbnKathir/0774IbnKathir.FusulMinSira/'
          '0774IbnKathir.FusulMinSira.Shamela0009241-ara1',
      title: 'الفصول في السيرة',
      author: _ibnKathir,
      edition:
          'تحقيق محمد العيد الخطراوي ومحيي الدين مستو، مؤسسة علوم القرآن، ط3، 1403هـ',
      readOnline: 'https://shamela.ws/book/9241',
    ),
  );

  static const sahaba = KnowledgeTrack(
    id: 'sahaba',
    topic: 'الصحابة',
    title: 'سير أعلام النبلاء',
    description: 'سير الخلفاء الراشدين والصحابة، للذهبي',
    kind: TrackKind.book,
    book: BookSource(
      repo: '0750AH',
      commit: '7c9c84d9f98581470aa2b7f8bee00ae285c5c707',
      path:
          'data/0748Dhahabi/0748Dhahabi.SiyarAclamNubala/'
          '0748Dhahabi.SiyarAclamNubala.Shamela0010906-ara1.mARkdown',
      title: 'سير أعلام النبلاء',
      author: 'الذهبي (ت 748هـ)',
      edition:
          'تحقيق مجموعة من المحققين بإشراف شعيب الأرناؤوط، مؤسسة الرسالة، ط3، 1405هـ',
      readOnline: 'https://shamela.ws/book/10906',
      startOffset: 2070823, // سير الخلفاء الراشدين
    ),
  );

  static const islamicHistory = KnowledgeTrack(
    id: 'islamic-history',
    topic: 'التاريخ الإسلامي',
    title: 'البداية والنهاية',
    description: 'تاريخ الإسلام سنةً بعد سنة من خلافة أبي بكر، لابن كثير',
    kind: TrackKind.book,
    book: BookSource(
      repo: '0775AH',
      commit: '61b0c7891699554aeff8dffdb8b1a2a59d2d22ab',
      path:
          'data/0774IbnKathir/0774IbnKathir.Bidaya/'
          '0774IbnKathir.Bidaya.Shamela0004445-ara1.completed',
      title: 'البداية والنهاية',
      author: _ibnKathir,
      edition: 'تحقيق عبد الله بن عبد المحسن التركي، دار هجر، ط1، 1418هـ',
      readOnline: 'https://shamela.ws/book/4445',
      startOffset: 8806896, // سنة إحدى عشرة، خلافة أبي بكر
    ),
  );

  static const fiqh = KnowledgeTrack(
    id: 'fiqh',
    topic: 'الفقه',
    title: 'عمدة الأحكام',
    description: 'أحاديث الأحكام من الصحيحين، لعبد الغني المقدسي',
    kind: TrackKind.book,
    book: BookSource(
      repo: '0600AH',
      commit: 'ea4bdc6517a49d07106f223aa0869aa7c21b9589',
      path:
          'data/0600CabdGhaniMaqdisi/0600CabdGhaniMaqdisi.CumdatAhkam/'
          '0600CabdGhaniMaqdisi.CumdatAhkam.Shamela0006075-ara1',
      title: 'عمدة الأحكام من كلام خير الأنام',
      author: 'عبد الغني المقدسي (ت 600هـ)',
      edition: 'تحقيق محمود الأرناؤوط، دار الثقافة العربية، ط2، 1408هـ',
      readOnline: 'https://shamela.ws/book/6075',
      startOffset: 5478, // كتاب الطهارة
      minChars: 500,
      maxChars: 1800,
    ),
  );

  static const hadith40 = KnowledgeTrack(
    id: 'hadith40',
    topic: 'الحديث',
    title: 'الأربعون النووية',
    description: 'أحاديث جامعة لأصول الدين، للنووي',
    kind: TrackKind.book,
    book: BookSource(
      repo: '0700AH',
      commit: '3d8ff4e7b035aaa4ca5dda52c7322645f3401dcf',
      path:
          'data/0676Nawawi/0676Nawawi.ArbacunaNawawiyya/'
          '0676Nawawi.ArbacunaNawawiyya.Shamela0012836-ara1.mARkdown',
      title: 'الأربعون النووية',
      author: 'النووي (ت 676هـ)',
      edition: 'دار المنهاج، بيروت، ط1، 1430هـ',
      readOnline: 'https://shamela.ws/book/12836',
      startOffset: 6477, // الحديث الأول
      minChars: 100,
      maxChars: 3000,
    ),
  );

  static const aqeedah = KnowledgeTrack(
    id: 'aqeedah',
    topic: 'العقيدة',
    title: 'العقيدة الطحاوية',
    description: 'متن في عقيدة أهل السنة والجماعة، للطحاوي',
    kind: TrackKind.book,
    book: BookSource(
      repo: '0325AH',
      commit: '089e665b4958e0f145a46941987fb81cf3dda1b8',
      path:
          'data/0321Tahawi/0321Tahawi.MatnCaqida/'
          '0321Tahawi.MatnCaqida.JK000126-ara1',
      title: 'متن العقيدة الطحاوية',
      author: 'أبو جعفر الطحاوي (ت 321هـ)',
      edition: 'تحقيق محمد ناصر الدين الألباني، المكتب الإسلامي',
      minChars: 900,
      maxChars: 1200,
    ),
  );

  static const modernWorld = KnowledgeTrack(
    id: 'modern-world',
    topic: 'كيف تشكّل العالم الحديث',
    title: 'أحداث صنعت عالمنا',
    description: 'من الحروب الصليبية إلى الربيع العربي، من ويكيبيديا العربية',
    kind: TrackKind.wikiSeries,
    articles: [
      'حملات صليبية',
      'سقوط بغداد (1258)',
      'فتح القسطنطينية',
      'سقوط الأندلس',
      'عصر الاستكشاف',
      'يوهان غوتنبرغ',
      'إصلاح بروتستانتي',
      'صلح وستفاليا',
      'ثورة علمية',
      'عصر التنوير',
      'الثورة الصناعية',
      'الثورة الأمريكية',
      'الثورة الفرنسية',
      'الحملة الفرنسية على مصر وسوريا',
      'استعمار',
      'قناة السويس',
      'الحرب العالمية الأولى',
      'اتفاقية سايكس بيكو',
      'وعد بلفور',
      'إلغاء الخلافة العثمانية',
      'الثورة الروسية',
      'الكساد الكبير',
      'الحرب العالمية الثانية',
      'الأمم المتحدة',
      'النكبة',
      'الحرب الباردة',
      'إنهاء الاستعمار',
      'العدوان الثلاثي',
      'حرب 1967',
      'حظر النفط 1973',
      'الثورة الإسلامية في إيران',
      'الحرب السوفيتية في أفغانستان',
      'سقوط جدار برلين',
      'تفكك الاتحاد السوفيتي',
      'عولمة',
      'إنترنت',
      'هجمات 11 سبتمبر',
      'الربيع العربي',
    ],
  );

  static const onThisDay = KnowledgeTrack(
    id: 'on-this-day',
    topic: 'تاريخ العالم',
    title: 'حدث في مثل هذا اليوم',
    description: 'أحداث من تاريخ العالم وقعت في مثل هذا اليوم',
    kind: TrackKind.onThisDay,
  );

  /// Tracks a weekday can be given, in library order.
  static const scheduled = [
    seerah,
    sahaba,
    islamicHistory,
    fiqh,
    hadith40,
    aqeedah,
    modernWorld,
  ];

  static const all = [...scheduled, onThisDay];

  static KnowledgeTrack? byId(String id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }
}
