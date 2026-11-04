/// Whether a part of a country's story is a fall, a rise, or both.
enum StoryMood {
  fall('سقوط'),
  rise('نهوض'),
  mixed('تحوّل');

  const StoryMood(this.label);

  final String label;
}

enum StoryGroup {
  ruin('نهضت بعد الخراب'),
  long('سقطت طويلاً ثم عادت'),
  near('قريبة من عالمك');

  const StoryGroup(this.label);

  final String label;
}

/// Problems that repeat across countries. Parts are tagged with them, which
/// is what lets you follow one problem through different countries.
enum StoryPattern {
  war('الحرب والدمار'),
  occupation('الاحتلال والتدخل الأجنبي'),
  division('الانقسام والحرب الأهلية'),
  economy('انهيار الاقتصاد والديون'),
  corruption('الفساد وضعف الدولة'),
  tyranny('الاستبداد'),
  identity('الهوية والكراهية'),
  education('التعليم والعلم'),
  land('الأرض والفلاحون'),
  industry('الصناعة والتجارة'),
  reform('الإصلاح وبناء الدولة'),
  reconciliation('المصالحة والمحاسبة');

  const StoryPattern(this.label);

  final String label;
}

/// One part of the story. Older parts fill the seven fixed sections; rewritten
/// ones are long chapters ([story], with `## heading` lines) that end with a
/// plain summary of the problem and the fix, then the historians' arguments.
class StoryPart {
  const StoryPart({
    required this.index,
    required this.title,
    required this.period,
    required this.mood,
    required this.patterns,
    required this.oneLine,
    required this.debate,
    this.situation = '',
    this.problem = '',
    this.failed = '',
    this.turning = '',
    this.fix = '',
    this.broken = '',
    this.story = '',
    this.takeaway = '',
  });

  final int index;
  final String title;

  /// e.g. ١٩١٨–١٩٣٣.
  final String period;
  final StoryMood mood;
  final List<StoryPattern> patterns;

  /// The part in one sentence, for lists and comparisons.
  final String oneLine;
  final String situation;
  final String problem;
  final String failed;
  final String turning;
  final String fix;
  final String broken;
  final String debate;
  final String story;
  final String takeaway;

  bool get isChapter => story.isNotEmpty;

  List<({String heading, String body})> get sections => isChapter
      ? [
          ..._storySections(story),
          (heading: 'الخلاصة: المشكلة وما حلّها', body: takeaway),
          (heading: 'أين يختلف المؤرخون', body: debate),
        ]
      : [
          (heading: 'الوضع', body: situation),
          (heading: 'المشكلة الحقيقية', body: problem),
          (heading: 'ما جرّبوه ففشل', body: failed),
          (heading: 'نقطة التحول', body: turning),
          (heading: 'الإصلاح البطيء', body: fix),
          (heading: 'ما بقي مكسوراً', body: broken),
          (heading: 'أين يختلف المؤرخون', body: debate),
        ];

  static List<({String heading, String body})> _storySections(String story) {
    final out = <({String heading, String body})>[];
    var heading = '';
    final body = StringBuffer();
    void flush() {
      final text = body.toString().trim();
      body.clear();
      if (text.isNotEmpty) out.add((heading: heading, body: text));
    }

    for (final line in story.split('\n')) {
      if (line.startsWith('## ')) {
        flush();
        heading = line.substring(3).trim();
      } else {
        body.writeln(line);
      }
    }
    flush();
    return out;
  }

  String get fullText =>
      sections.map((s) => '${s.heading}\n${s.body}').join('\n\n');

  int get words => fullText.split(RegExp(r'\s+')).length;
}

class StoryCountry {
  const StoryCountry({
    required this.id,
    required this.name,
    required this.group,
    required this.tagline,
    required this.parts,
    required this.sources,
    this.note,
  });

  final String id;
  final String name;
  final StoryGroup group;
  final String tagline;
  final List<StoryPart> parts;
  final List<({String title, String? url})> sources;

  /// How the text was checked, shown above the sources.
  final String? note;

  /// Reading time at about 180 words a minute.
  int get minutes => (parts.fold<int>(0, (s, p) => s + p.words) / 180).ceil();

  /// A country's story from its text file:
  ///
  ///     @name ألمانيا
  ///     @part
  ///     @title …
  ///     @situation
  ///     paragraphs until the next @key…
  static StoryCountry parse(String id, String text) {
    final head = <String, String>{};
    final sources = <({String title, String? url})>[];
    final parts = <Map<String, String>>[];
    Map<String, String>? part;
    String? section;
    final body = StringBuffer();

    void flush() {
      if (section == null) return;
      final value = body.toString().trim();
      body.clear();
      if (section == 'sources') {
        for (final l in value.split('\n').where((l) => l.trim().isNotEmpty)) {
          final bits = l.split('|');
          sources.add((
            title: bits.first.trim(),
            url: bits.length > 1 ? bits[1].trim() : null,
          ));
        }
      } else {
        (part ?? head)[section!] = value;
      }
      section = null;
    }

    for (final line in text.split('\n')) {
      final m = RegExp(r'^@(\w+)\s*(.*)$').firstMatch(line);
      if (m == null) {
        if (section != null) body.writeln(line);
        continue;
      }
      flush();
      final key = m.group(1)!;
      final rest = m.group(2)!.trim();
      if (key == 'part') {
        parts.add(part = {});
      } else if (rest.isNotEmpty) {
        (part ?? head)[key] = rest;
      } else {
        section = key;
      }
    }
    flush();

    String need(Map<String, String> from, String key) {
      final v = from[key];
      if (v == null || v.isEmpty) {
        throw FormatException(
          '$id: missing @$key in ${from['title'] ?? 'head'}',
        );
      }
      return v;
    }

    bool isChapter(Map<String, String> p) => p['story']?.isNotEmpty ?? false;

    return StoryCountry(
      id: id,
      name: need(head, 'name'),
      group: StoryGroup.values.byName(need(head, 'group')),
      tagline: need(head, 'tagline'),
      sources: sources,
      note: head['note'],
      parts: [
        for (final (i, p) in parts.indexed) _part(i, p, need, isChapter(p)),
      ],
    );
  }

  static StoryPart _part(
    int i,
    Map<String, String> p,
    String Function(Map<String, String>, String) need,
    bool chapter,
  ) => StoryPart(
    index: i,
    title: need(p, 'title'),
    period: need(p, 'period'),
    mood: StoryMood.values.byName(need(p, 'mood')),
    patterns: [
      for (final t in need(p, 'patterns').split(','))
        StoryPattern.values.byName(t.trim()),
    ],
    oneLine: need(p, 'oneline'),
    debate: need(p, 'debate'),
    situation: chapter ? '' : need(p, 'situation'),
    problem: chapter ? '' : need(p, 'problem'),
    failed: chapter ? '' : need(p, 'failed'),
    turning: chapter ? '' : need(p, 'turning'),
    fix: chapter ? '' : need(p, 'fix'),
    broken: chapter ? '' : need(p, 'broken'),
    story: p['story'] ?? '',
    takeaway: chapter ? need(p, 'takeaway') : '',
  );
}
