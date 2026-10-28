import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/entities/feed_article.dart';
import '../../domain/repositories/rss_repository.dart';
import '../parsers/feed_parser.dart';

class RssRemoteDataSource {
  RssRemoteDataSource(this._client);

  final http.Client _client;

  static const _timeout = Duration(seconds: 20);
  static const _headers = {
    'User-Agent': 'MyKit RSS Reader (Android)',
    'Accept':
        'application/rss+xml, application/atom+xml, application/xml;q=0.9, '
        'text/xml;q=0.9, text/html;q=0.8, */*;q=0.5',
  };

  /// Common feed locations tried when a page doesn't advertise its feed.
  static const _guessPaths = [
    '/feed',
    '/rss',
    '/rss.xml',
    '/feed.xml',
    '/atom.xml',
    '/index.xml',
  ];

  static final _alternateLink = RegExp(
    r'''<link\b[^>]*type\s*=\s*["']application/(?:rss|atom)\+xml["'][^>]*>''',
    caseSensitive: false,
  );
  static final _href = RegExp(
    r'''href\s*=\s*["']([^"']+)["']''',
    caseSensitive: false,
  );

  /// Resolves [input] to a feed: direct feed URL, a page that links to one,
  /// or a site with a feed at a common path.
  Future<FeedPreview> discover(String input) async {
    final uri = normalize(input);
    final body = await _get(uri);

    final direct = FeedParser.tryParse(body);
    if (direct != null) return FeedPreview(url: uri.toString(), feed: direct);

    final candidates = <Uri>[
      for (final tag in _alternateLink.allMatches(body))
        if (_href.firstMatch(tag.group(0)!) case final m?)
          uri.resolve(_decodeAmp(m.group(1)!)),
      for (final path in _guessPaths)
        Uri(
          scheme: uri.scheme,
          host: uri.host,
          port: uri.hasPort ? uri.port : null,
          path: path,
        ),
    ];

    for (final candidate in candidates) {
      try {
        final parsed = FeedParser.tryParse(await _get(candidate));
        if (parsed != null) {
          return FeedPreview(url: candidate.toString(), feed: parsed);
        }
      } catch (_) {
        // Try the next candidate.
      }
    }
    throw const FeedException('No RSS or Atom feed found at this address.');
  }

  Future<ParsedFeed> fetch(String url) async {
    final parsed = FeedParser.tryParse(await _get(Uri.parse(url)));
    if (parsed == null) {
      throw const FeedException('The address no longer returns a valid feed.');
    }
    return parsed;
  }

  static Uri normalize(String input) {
    var text = input.trim();
    if (text.isEmpty) throw const FeedException('Enter a feed or website URL.');
    if (!text.contains('://')) text = 'https://$text';
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) {
      throw const FeedException('That doesn\'t look like a valid URL.');
    }
    return uri;
  }

  Future<String> _get(Uri uri) async {
    final http.Response res;
    try {
      res = await _client.get(uri, headers: _headers).timeout(_timeout);
    } catch (_) {
      throw const FeedException(
        'Could not connect. Check the URL and your internet.',
      );
    }
    if (res.statusCode >= 400) {
      throw FeedException('Server responded with ${res.statusCode}.');
    }
    return _decode(res);
  }

  /// Decodes using the declared charset; defaults to UTF-8.
  static String _decode(http.Response res) {
    final bytes = res.bodyBytes;
    final head = latin1.decode(bytes.take(200).toList()).toLowerCase();
    final contentType = (res.headers['content-type'] ?? '').toLowerCase();
    final isLatin = RegExp(
      r'iso-8859-1|windows-1252|latin1',
    ).hasMatch('$contentType $head');
    return isLatin
        ? latin1.decode(bytes)
        : utf8.decode(bytes, allowMalformed: true);
  }

  static String _decodeAmp(String s) => s.replaceAll('&amp;', '&');
}
