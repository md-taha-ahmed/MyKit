import 'dart:convert';

import 'package:http/http.dart' as http;

/// Best-effort readable text of a web article (paragraphs, headings and list
/// items), for feeds that only ship a teaser.
class ArticleTextSource {
  ArticleTextSource(this._client);

  final http.Client _client;

  static const _maxChars = 20000;

  Future<String?> fetch(String url) async {
    try {
      final res = await _client
          .get(
            Uri.parse(url),
            headers: const {
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/130 Mobile Safari/537.36',
            },
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      return extract(utf8.decode(res.bodyBytes, allowMalformed: true));
    } catch (_) {
      return null;
    }
  }

  /// Exposed for tests.
  static String? extract(String html) {
    var doc = html
        .replaceAll(
          RegExp(
            r'<(script|style|noscript|nav|header|footer|aside|form|svg)\b[\s\S]*?</\1>',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ');
    // Prefer the <article> element when there is one.
    final article =
        RegExp(r'<article\b[\s\S]*?</article>', caseSensitive: false)
            .allMatches(doc)
            .map((m) => m.group(0)!)
            .fold<String>('', (best, a) => a.length > best.length ? a : best);
    if (article.length > 500) doc = article;

    final blocks = RegExp(
      r'<(p|h[1-4]|li|blockquote)\b[^>]*>([\s\S]*?)</\1>',
      caseSensitive: false,
    ).allMatches(doc);
    final lines = <String>[];
    for (final m in blocks) {
      final text = _clean(m.group(2)!);
      if (text.length < 25 && !m.group(1)!.toLowerCase().startsWith('h')) {
        continue;
      }
      if (text.isNotEmpty) lines.add(text);
    }
    final text = lines.join('\n\n');
    if (text.length < 200) return null;
    return text.length > _maxChars ? text.substring(0, _maxChars) : text;
  }

  static String _clean(String s) => s
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&rsquo;', "'")
      .replaceAll('&lsquo;', "'")
      .replaceAll('&ldquo;', '"')
      .replaceAll('&rdquo;', '"')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAllMapped(
        RegExp(r'&#(\d+);'),
        (m) => String.fromCharCode(int.parse(m.group(1)!)),
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
