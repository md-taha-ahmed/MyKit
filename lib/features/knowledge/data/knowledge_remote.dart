import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../rss/data/parsers/html_text.dart';
import '../domain/knowledge_models.dart';
import 'openiti_parser.dart';

class KnowledgeException implements Exception {
  const KnowledgeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The next passage of a book, and where the one after it starts.
typedef BookPassage = ({Lesson lesson, TrackPosition next});

/// Lessons from the books (a few dozen KB per lesson, fetched with HTTP
/// range requests) and from Arabic Wikipedia.
class KnowledgeRemote {
  KnowledgeRemote(this._client);

  final http.Client _client;

  static const _timeout = Duration(seconds: 25);
  static const _userAgent =
      'MyKit/1.0 (personal learning app; https://github.com/md-taha-ahmed/MyKit)';

  Future<http.Response> _get(Uri uri, [Map<String, String>? headers]) async {
    try {
      final res = await _client
          .get(uri, headers: {'User-Agent': _userAgent, ...?headers})
          .timeout(_timeout);
      if (res.statusCode >= 400) {
        throw KnowledgeException('تعذّر التحميل (${res.statusCode}).');
      }
      return res;
    } on SocketException {
      throw const KnowledgeException('لا يوجد اتصال بالإنترنت.');
    } on KnowledgeException {
      rethrow;
    } catch (_) {
      throw const KnowledgeException('انتهت مهلة الاتصال، حاول مرة أخرى.');
    }
  }

  // ---------------------------------------------------------------------------
  // Books
  // ---------------------------------------------------------------------------

  Future<BookPassage> nextPassage(
    KnowledgeTrack track,
    TrackPosition position,
  ) async {
    final book = track.book!;
    var offset = position.offset ?? book.startOffset;
    var heading = position.heading;
    var size = 48 * 1024;

    for (var attempt = 0; attempt < 8; attempt++) {
      final res = await _get(book.rawUrl, {
        'Range': 'bytes=$offset-${offset + size - 1}',
        // Ranges must count bytes of the file itself, not of a gzip of it.
        'Accept-Encoding': 'identity',
      });
      final bytes = res.bodyBytes;
      final total = _totalSize(res) ?? offset + bytes.length;
      final atEnd = res.statusCode == 200 || offset + bytes.length >= total;
      final chunk = res.statusCode == 200 && offset > 0
          ? Uint8List.sublistView(bytes, offset)
          : bytes;

      final parsed = OpenItiParser.parse(
        chunk,
        atFileEnd: atEnd,
        minChars: book.minChars,
        maxChars: book.maxChars,
        heading: heading,
      );
      if (parsed.cutShort) {
        size *= 2;
        continue;
      }
      if (parsed.isEmpty) {
        if (parsed.reachedEnd) {
          throw const KnowledgeException('أكملت هذا الكتاب، بارك الله فيك.');
        }
        // Only headings (a title page…): skip them.
        offset += parsed.consumed;
        heading = parsed.lastHeading;
        continue;
      }

      final firstHeading = parsed.blocks.first.heading
          ? parsed.blocks.first.text
          : null;
      final title = firstHeading ?? heading ?? book.title;
      final location = OpenItiParser.location(
        parsed.pages,
        volumes: parsed.pages.any((p) => p.volume > 1),
      );
      final lesson = Lesson(
        id: '${track.id}@$offset',
        trackId: track.id,
        title: title,
        blocks: parsed.blocks,
        reference: LessonReference(
          source: book.title,
          author: book.author,
          edition: book.edition,
          // The chapter this passage continues (when it isn't the title).
          chapter: heading != null && heading != title ? heading : null,
          location: location,
          url: book.sourceUrl,
          checkUrl: book.readOnline,
        ),
      );
      return (
        lesson: lesson,
        next: TrackPosition(
          offset: offset + parsed.consumed,
          heading: parsed.lastHeading,
          total: total,
          finished: parsed.reachedEnd,
        ),
      );
    }
    throw const KnowledgeException('تعذّر قراءة هذا الجزء من الكتاب.');
  }

  static int? _totalSize(http.Response res) {
    final range = res.headers['content-range']; // bytes 0-6000/379136
    if (range == null) return null;
    return int.tryParse(range.split('/').last);
  }

  // ---------------------------------------------------------------------------
  // Wikipedia
  // ---------------------------------------------------------------------------

  static const _wiki = 'ar.wikipedia.org';

  /// The introduction of an article, exactly as written, pinned to the
  /// revision that was read.
  Future<Lesson> article(KnowledgeTrack track, int index) async {
    final title = track.articles[index];
    final res = await _get(
      Uri.https(_wiki, '/w/api.php', {
        'action': 'query',
        'format': 'json',
        'formatversion': '2',
        'redirects': '1',
        'prop': 'extracts|revisions|info',
        'inprop': 'url',
        'rvprop': 'ids',
        'exintro': '1',
        'explaintext': '1',
        'titles': title,
      }),
    );
    final pages =
        ((jsonDecode(res.body) as Map)['query'] as Map?)?['pages'] as List?;
    final page = pages == null || pages.isEmpty ? null : pages.first as Map;
    final extract = (page?['extract'] as String?)?.trim() ?? '';
    if (page == null || page['missing'] == true || extract.isEmpty) {
      throw KnowledgeException('لم أجد مقالة «$title».');
    }
    final revision = ((page['revisions'] as List?)?.first as Map?)?['revid'];
    final name = page['title'] as String;
    final live =
        page['fullurl'] as String? ??
        'https://$_wiki/wiki/${Uri.encodeComponent(name.replaceAll(' ', '_'))}';
    return Lesson(
      id: '${track.id}#$index',
      trackId: track.id,
      title: name,
      blocks: [
        for (final p in extract.split(RegExp(r'\n+')))
          if (p.trim().isNotEmpty) LessonBlock(p.trim()),
      ],
      reference: LessonReference(
        source: 'ويكيبيديا العربية',
        chapter: 'مقالة «$name» (المقدمة)',
        url: revision == null
            ? live
            : 'https://$_wiki/w/index.php?oldid=$revision',
        checkUrl: live,
      ),
    );
  }

  static const _months = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', //
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];

  static String dayName(DateTime d) => '${d.day} ${_months[d.month - 1]}';

  /// A handful of events from Arabic Wikipedia's "on this day" list, oldest
  /// first, spread across the centuries.
  Future<Lesson> onThisDay(KnowledgeTrack track, DateTime date) async {
    final mm = date.month.toString().padLeft(2, '0');
    final dd = date.day.toString().padLeft(2, '0');
    final res = await _get(
      Uri.https(_wiki, '/api/rest_v1/feed/onthisday/events/$mm/$dd'),
    );
    final events = [
      for (final e in ((jsonDecode(res.body) as Map)['events'] as List? ?? []))
        if (e is Map && e['text'] is String && e['year'] is num)
          (
            year: (e['year'] as num).toInt(),
            text: (e['text'] as String).trim(),
          ),
    ]..sort((a, b) => a.year.compareTo(b.year));
    if (events.isEmpty) {
      throw const KnowledgeException('لا توجد أحداث لهذا اليوم.');
    }
    const count = 6;
    final picked = events.length <= count
        ? events
        : [
            for (var i = 0; i < count; i++)
              events[(i * (events.length - 1) / (count - 1)).round()],
          ];
    final day = dayName(date);
    return Lesson(
      id: '${track.id}@${dayKey(date)}',
      trackId: track.id,
      title: 'في مثل هذا اليوم، $day',
      day: dayKey(date),
      blocks: [
        for (final e in picked) ...[
          LessonBlock(
            e.year < 0 ? '${-e.year} ق.م' : '${e.year}م',
            heading: true,
          ),
          LessonBlock(e.text),
        ],
      ],
      reference: LessonReference(
        source: 'ويكيبيديا العربية',
        chapter: 'صفحة «$day»',
        url:
            'https://$_wiki/wiki/${Uri.encodeComponent(day.replaceAll(' ', '_'))}',
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Watched pages (sites without a feed)
  // ---------------------------------------------------------------------------

  static final _anchor = RegExp(
    r'''<a\b[^>]*?href\s*=\s*["']([^"'#]+)["'][^>]*>(.*?)</a>''',
    caseSensitive: false,
    dotAll: true,
  );
  static final _articleLike = RegExp(r'\d{3,}|/\d{4}/');
  static final _skipPath = RegExp(
    r'/(tag|tags|category|categories|author|login|register|search|page)/|'
    r'\.(jpg|png|pdf|zip|mp3)$',
    caseSensitive: false,
  );

  /// Links on [pageUrl] that look like articles, in page order.
  Future<({String title, List<({String title, String url})> links})> watch(
    String pageUrl,
  ) async {
    final uri = Uri.parse(pageUrl);
    final res = await _get(uri, {'Accept': 'text/html'});
    final body = utf8.decode(res.bodyBytes, allowMalformed: true);
    final titleMatch = RegExp(
      r'<title[^>]*>(.*?)</title>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(body);
    final seen = <String>{};
    final all = <({String title, String url})>[];
    for (final m in _anchor.allMatches(body)) {
      final href = HtmlText.decodeEntities(m.group(1)!.trim());
      final link = uri.resolve(href);
      if (!link.scheme.startsWith('http')) continue;
      final sameSite =
          link.host == uri.host ||
          link.host.endsWith('.${uri.host.replaceFirst('www.', '')}');
      if (!sameSite || _skipPath.hasMatch(link.path)) continue;
      if (link.path.length < 2 || link.path == uri.path) continue;
      final text = HtmlText.toPlain(
        m.group(2)!,
      ).replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.length < 12 || text.length > 220) continue;
      final url = link.removeFragment().toString();
      if (seen.add(url)) all.add((title: text, url: url));
    }
    final articles = all.where(
      (l) => _articleLike.hasMatch(Uri.parse(l.url).path),
    );
    return (
      title: HtmlText.toPlain(titleMatch?.group(1) ?? uri.host).trim(),
      links: (articles.length >= 3 ? articles : all).take(40).toList(),
    );
  }
}
