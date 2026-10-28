import 'package:xml/xml.dart';

import '../../domain/entities/feed_article.dart';
import 'html_text.dart';

/// Parses RSS 2.0, RSS 1.0 (RDF) and Atom documents.
abstract final class FeedParser {
  static const _summaryLength = 280;
  static const _contentLength = 8000;

  /// Returns null if [source] isn't a feed document.
  static ParsedFeed? tryParse(String source) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(source);
    } on XmlException {
      return null;
    }
    final root = doc.rootElement;
    return switch (root.name.local.toLowerCase()) {
      'rss' => _parseRss(root),
      'rdf' => _parseRss(root),
      'feed' => _parseAtom(root),
      _ => null,
    };
  }

  // ---------------------------------------------------------------------------
  // RSS 2.0 / 1.0
  // ---------------------------------------------------------------------------

  static ParsedFeed _parseRss(XmlElement root) {
    final channel = _child(root, 'channel') ?? root;
    // RSS 2.0 nests items in <channel>; RSS 1.0 puts them next to it.
    final items = [
      ..._children(channel, 'item'),
      if (channel != root) ..._children(root, 'item'),
    ];

    return ParsedFeed(
      title: _text(channel, 'title') ?? 'Untitled feed',
      siteUrl: _text(channel, 'link'),
      articles: items.map(_rssItem).toList(),
    );
  }

  static FeedArticle _rssItem(XmlElement item) {
    final description = _text(item, 'description') ?? '';
    final encoded = _text(item, 'encoded') ?? ''; // content:encoded
    final html = encoded.isNotEmpty ? encoded : description;
    final link = _text(item, 'link');

    return _article(
      key: _text(item, 'guid') ?? link,
      title: _text(item, 'title'),
      link: link,
      summaryHtml: description.isNotEmpty ? description : html,
      contentHtml: html,
      imageUrl: _mediaImage(item) ?? HtmlText.firstImage(html),
      author: _text(item, 'creator') ?? _text(item, 'author'),
      date: _parseDate(_text(item, 'pubDate') ?? _text(item, 'date')),
    );
  }

  // ---------------------------------------------------------------------------
  // Atom
  // ---------------------------------------------------------------------------

  static ParsedFeed _parseAtom(XmlElement feed) {
    return ParsedFeed(
      title: _text(feed, 'title') ?? 'Untitled feed',
      siteUrl: _atomLink(feed),
      articles: _children(feed, 'entry').map(_atomEntry).toList(),
    );
  }

  static FeedArticle _atomEntry(XmlElement entry) {
    final summary = _text(entry, 'summary') ?? '';
    final content = _text(entry, 'content') ?? '';
    final html = content.isNotEmpty ? content : summary;
    final link = _atomLink(entry);
    final author = _child(entry, 'author');

    return _article(
      key: _text(entry, 'id') ?? link,
      title: _text(entry, 'title'),
      link: link,
      summaryHtml: summary.isNotEmpty ? summary : html,
      contentHtml: html,
      imageUrl: _mediaImage(entry) ?? HtmlText.firstImage(html),
      author: author == null ? null : _text(author, 'name'),
      date: _parseDate(_text(entry, 'published') ?? _text(entry, 'updated')),
    );
  }

  static String? _atomLink(XmlElement el) {
    String? fallback;
    for (final link in _children(el, 'link')) {
      final href = link.getAttribute('href');
      if (href == null) continue;
      final rel = link.getAttribute('rel');
      if (rel == null || rel == 'alternate') return href;
      fallback ??= href;
    }
    return fallback;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static FeedArticle _article({
    required String? key,
    required String? title,
    required String? link,
    required String summaryHtml,
    required String contentHtml,
    required String? imageUrl,
    required String? author,
    required DateTime? date,
  }) {
    final cleanTitle = HtmlText.toPlain(title ?? '');
    final content = HtmlText.toPlain(contentHtml);
    final summary = HtmlText.toPlain(summaryHtml).replaceAll('\n', ' ');
    return FeedArticle(
      id: key ?? cleanTitle,
      feedId: '',
      title: cleanTitle.isEmpty ? '(No title)' : cleanTitle,
      link: link?.trim(),
      summary: HtmlText.truncate(summary, _summaryLength),
      content: HtmlText.truncate(content, _contentLength),
      imageUrl: imageUrl,
      author: author?.trim().isEmpty ?? true ? null : author!.trim(),
      publishedAt: date,
    );
  }

  /// media:thumbnail, media:content (image) or an image enclosure.
  static String? _mediaImage(XmlElement item) {
    // Prefer the largest image the feed offers: full media:content/enclosure
    // images beat thumbnails, and a bigger declared width beats a smaller one.
    String? best;
    var bestScore = -1;
    for (final el in item.descendantElements) {
      final name = el.name.local;
      final url = el.getAttribute('url');
      if (url == null) continue;
      final type = el.getAttribute('type') ?? '';
      final medium = el.getAttribute('medium') ?? '';
      final isFull =
          (name == 'content' || name == 'enclosure') &&
          (type.startsWith('image/') || medium == 'image');
      if (!isFull && name != 'thumbnail') continue;
      final width = int.tryParse(el.getAttribute('width') ?? '') ?? 0;
      final score = width + (isFull ? 100000 : 0);
      if (score > bestScore) {
        best = url;
        bestScore = score;
      }
    }
    return best;
  }

  static XmlElement? _child(XmlElement el, String local) {
    for (final c in el.childElements) {
      if (c.name.local == local) return c;
    }
    return null;
  }

  static Iterable<XmlElement> _children(XmlElement el, String local) =>
      el.childElements.where((c) => c.name.local == local);

  /// First non-empty text among children named [local]. (RSS channels often
  /// have an empty `<atom:link href>` before the real `<link>`.)
  static String? _text(XmlElement el, String local) {
    for (final c in _children(el, local)) {
      final text = c.innerText.trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Dates: RFC 822 (RSS) and ISO 8601 (Atom, dc:date)
  // ---------------------------------------------------------------------------

  static final _rfc822 = RegExp(
    r'^(?:\w{3},\s*)?(\d{1,2})\s+(\w{3})\w*\s+(\d{2,4})\s+'
    r'(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([+-]\d{4}|[A-Za-z]+)?',
  );
  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, //
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };
  static const _zones = {
    'gmt': 0, 'ut': 0, 'utc': 0, 'z': 0, //
    'est': -5, 'edt': -4, 'cst': -6, 'cdt': -5,
    'mst': -7, 'mdt': -6, 'pst': -8, 'pdt': -7,
  };

  static DateTime? _parseDate(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso.toLocal();

    final m = _rfc822.firstMatch(s);
    if (m == null) return null;
    final month = _months[m.group(2)!.toLowerCase()];
    if (month == null) return null;
    var year = int.parse(m.group(3)!);
    if (year < 100) year += 2000;

    var offsetMinutes = 0;
    final zone = m.group(7);
    if (zone != null) {
      if (zone.startsWith('+') || zone.startsWith('-')) {
        final sign = zone.startsWith('-') ? -1 : 1;
        offsetMinutes =
            sign *
            (int.parse(zone.substring(1, 3)) * 60 +
                int.parse(zone.substring(3, 5)));
      } else {
        offsetMinutes = (_zones[zone.toLowerCase()] ?? 0) * 60;
      }
    }

    final utc = DateTime.utc(
      year,
      month,
      int.parse(m.group(1)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6) ?? '0'),
    ).subtract(Duration(minutes: offsetMinutes));
    return utc.toLocal();
  }
}
