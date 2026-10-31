/// A book in the OpenITI corpus (open, machine-readable classical Arabic
/// texts), pinned to one commit so byte offsets never move.
class BookSource {
  const BookSource({
    required this.repo,
    required this.commit,
    required this.path,
    required this.title,
    required this.author,
    required this.edition,
    this.readOnline,
    this.startOffset = 0,
    this.minChars = 1200,
    this.maxChars = 2400,
  });

  final String repo;
  final String commit;
  final String path;
  final String title;

  /// "ابن كثير (ت 774هـ)".
  final String author;

  /// Editor and publisher of the printed edition the text comes from.
  final String edition;

  /// The same book on al-Maktaba al-Shamela, for checking the original.
  final String? readOnline;

  /// Where the daily lessons begin (skips an editor's introduction…).
  final int startOffset;

  /// A lesson ends at the next chapter heading once it has [minChars], or at
  /// the end of a paragraph once it has [maxChars].
  final int minChars;
  final int maxChars;

  Uri get rawUrl => Uri.parse(
    'https://raw.githubusercontent.com/OpenITI/$repo/$commit/$path',
  );

  String get sourceUrl => 'https://github.com/OpenITI/$repo/blob/$commit/$path';
}

enum TrackKind { book, wikiSeries, onThisDay }

/// Something to learn from in order: a book, or a series of articles.
class KnowledgeTrack {
  const KnowledgeTrack({
    required this.id,
    required this.topic,
    required this.title,
    required this.description,
    required this.kind,
    this.book,
    this.articles = const [],
  });

  final String id;

  /// "السيرة النبوية", "الفقه"…
  final String topic;
  final String title;
  final String description;
  final TrackKind kind;
  final BookSource? book;

  /// Arabic Wikipedia article titles, in reading order ([TrackKind.wikiSeries]).
  final List<String> articles;
}

/// A heading or a paragraph of a lesson, exactly as in the source.
class LessonBlock {
  const LessonBlock(this.text, {this.heading = false});

  final String text;
  final bool heading;

  Map<String, dynamic> toJson() => {'t': text, if (heading) 'h': true};

  static LessonBlock fromJson(Map<String, dynamic> j) =>
      LessonBlock(j['t'] as String, heading: j['h'] == true);
}

/// Where a lesson's text comes from.
class LessonReference {
  const LessonReference({
    required this.source,
    required this.url,
    this.author,
    this.edition,
    this.chapter,
    this.location,
    this.checkUrl,
  });

  /// Book or site ("البداية والنهاية", "ويكيبيديا العربية").
  final String source;
  final String? author;
  final String? edition;
  final String? chapter;

  /// "ج9، ص412–413".
  final String? location;

  /// The exact text used (pinned file / article version).
  final String url;

  /// The source's own page (Shamela, the live article…).
  final String? checkUrl;

  Map<String, dynamic> toJson() => {
    'source': source,
    'url': url,
    'author': ?author,
    'edition': ?edition,
    'chapter': ?chapter,
    'location': ?location,
    'checkUrl': ?checkUrl,
  };

  static LessonReference fromJson(Map<String, dynamic> j) => LessonReference(
    source: j['source'] as String,
    url: j['url'] as String,
    author: j['author'] as String?,
    edition: j['edition'] as String?,
    chapter: j['chapter'] as String?,
    location: j['location'] as String?,
    checkUrl: j['checkUrl'] as String?,
  );
}

class Lesson {
  const Lesson({
    required this.id,
    required this.trackId,
    required this.title,
    required this.blocks,
    required this.reference,
    this.day,
  });

  final String id;
  final String trackId;
  final String title;
  final List<LessonBlock> blocks;
  final LessonReference reference;

  /// "2026-10-31" for a daily lesson, null for reading ahead.
  final String? day;

  String get plainText => blocks.map((b) => b.text).join('\n\n');

  Lesson copyWith({String? day}) => Lesson(
    id: id,
    trackId: trackId,
    title: title,
    blocks: blocks,
    reference: reference,
    day: day ?? this.day,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'track': trackId,
    'title': title,
    'blocks': [for (final b in blocks) b.toJson()],
    'ref': reference.toJson(),
    'day': ?day,
  };

  static Lesson fromJson(Map<String, dynamic> j) => Lesson(
    id: j['id'] as String,
    trackId: j['track'] as String,
    title: j['title'] as String,
    blocks: [
      for (final b in j['blocks'] as List)
        LessonBlock.fromJson(b as Map<String, dynamic>),
    ],
    reference: LessonReference.fromJson(j['ref'] as Map<String, dynamic>),
    day: j['day'] as String?,
  );
}

/// How far a track has been read.
class TrackPosition {
  const TrackPosition({
    this.offset,
    this.index = 0,
    this.heading,
    this.total,
    this.finished = false,
  });

  /// Byte offset in the book file (books).
  final int? offset;

  /// Next article (series).
  final int index;

  /// The chapter the next passage is in.
  final String? heading;

  /// File size, once known (for progress).
  final int? total;
  final bool finished;

  Map<String, dynamic> toJson() => {
    'offset': ?offset,
    'index': index,
    'heading': ?heading,
    'total': ?total,
    if (finished) 'finished': true,
  };

  static TrackPosition fromJson(Map<String, dynamic> j) => TrackPosition(
    offset: (j['offset'] as num?)?.toInt(),
    index: (j['index'] as num?)?.toInt() ?? 0,
    heading: j['heading'] as String?,
    total: (j['total'] as num?)?.toInt(),
    finished: j['finished'] == true,
  );
}

/// A website or channel followed in the Sources tab.
class KnowledgeSource {
  const KnowledgeSource({
    required this.id,
    required this.name,
    required this.url,
    this.feedUrl,
  });

  final String id;
  final String name;

  /// The page the user added.
  final String url;

  /// Its RSS/Atom feed; null when the site has none and its page is watched
  /// for new links instead.
  final String? feedUrl;

  bool get watchesPage => feedUrl == null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'feedUrl': ?feedUrl,
  };

  static KnowledgeSource fromJson(Map<String, dynamic> j) => KnowledgeSource(
    id: j['id'] as String,
    name: j['name'] as String,
    url: j['url'] as String,
    feedUrl: j['feedUrl'] as String?,
  );
}

class SourceItem {
  const SourceItem({
    required this.sourceId,
    required this.title,
    required this.url,
    required this.date,
    this.isNew = false,
  });

  final String sourceId;
  final String title;
  final String url;

  /// Published (feeds) or first seen (watched pages).
  final DateTime date;
  final bool isNew;

  SourceItem copyWith({bool? isNew}) => SourceItem(
    sourceId: sourceId,
    title: title,
    url: url,
    date: date,
    isNew: isNew ?? this.isNew,
  );

  Map<String, dynamic> toJson() => {
    's': sourceId,
    't': title,
    'u': url,
    'd': date.millisecondsSinceEpoch,
    if (isNew) 'n': true,
  };

  static SourceItem fromJson(Map<String, dynamic> j) => SourceItem(
    sourceId: j['s'] as String,
    title: j['t'] as String,
    url: j['u'] as String,
    date: DateTime.fromMillisecondsSinceEpoch((j['d'] as num).toInt()),
    isNew: j['n'] == true,
  );
}

/// When lessons come and which track each weekday reads.
class KnowledgeSettings {
  const KnowledgeSettings({
    this.schedule = defaultSchedule,
    this.notify = true,
    this.minutes = 8 * 60,
    this.aiHelper = true,
    this.sourceAlerts = true,
  });

  /// Weekday (1 = Monday … 7 = Sunday) → track id.
  final Map<int, String> schedule;
  final bool notify;

  /// Notification time, minutes after midnight.
  final int minutes;
  final bool aiHelper;

  /// Check the followed sites in the background and notify about new
  /// articles.
  final bool sourceAlerts;

  static const defaultSchedule = {
    6: 'seerah', // Saturday
    7: 'islamic-history',
    1: 'fiqh',
    2: 'sahaba',
    3: 'modern-world',
    4: 'aqeedah',
    5: 'hadith40', // Friday
  };

  KnowledgeSettings copyWith({
    Map<int, String>? schedule,
    bool? notify,
    int? minutes,
    bool? aiHelper,
    bool? sourceAlerts,
  }) => KnowledgeSettings(
    schedule: schedule ?? this.schedule,
    notify: notify ?? this.notify,
    minutes: minutes ?? this.minutes,
    aiHelper: aiHelper ?? this.aiHelper,
    sourceAlerts: sourceAlerts ?? this.sourceAlerts,
  );

  Map<String, dynamic> toJson() => {
    'schedule': {for (final e in schedule.entries) '${e.key}': e.value},
    'notify': notify,
    'minutes': minutes,
    'aiHelper': aiHelper,
    'sourceAlerts': sourceAlerts,
  };

  static KnowledgeSettings fromJson(Map<String, dynamic> j) =>
      KnowledgeSettings(
        schedule: {
          for (final e in ((j['schedule'] as Map?) ?? defaultSchedule).entries)
            int.parse('${e.key}'): e.value as String,
        },
        notify: j['notify'] as bool? ?? true,
        minutes: (j['minutes'] as num?)?.toInt() ?? 8 * 60,
        aiHelper: j['aiHelper'] as bool? ?? true,
        sourceAlerts: j['sourceAlerts'] as bool? ?? true,
      );
}

String dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
