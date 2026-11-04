import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../../core/i18n/i18n.dart';
import '../../../../core/utils/charsets.dart';

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
    throw FeedException(tr('No RSS or Atom feed found at this address.'));
  }

  Future<ParsedFeed> fetch(String url) async {
    final parsed = FeedParser.tryParse(await _get(Uri.parse(url)));
    if (parsed == null) {
      throw FeedException(tr('The address no longer returns a valid feed.'));
    }
    return parsed;
  }

  static Uri normalize(String input) {
    var text = input.trim();
    if (text.isEmpty) throw FeedException(tr('Enter a feed or website URL.'));
    if (!text.contains('://')) text = 'https://$text';
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) {
      throw FeedException(tr('That doesn\'t look like a valid URL.'));
    }
    return uri;
  }

  /// Up to 3 tries for rate limits, server errors and timeouts, waiting as
  /// the server asks (Retry-After, capped) or a little longer each time.
  Future<String> _get(Uri uri) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await _getOnce(uri);
      } on FeedException catch (e) {
        if (!e.transient || attempt >= 3) rethrow;
        await Future<void>.delayed(
          e.retryAfter ?? Duration(seconds: 2 * attempt),
        );
      }
    }
  }

  Future<String> _getOnce(Uri uri) async {
    final http.Response res;
    try {
      res = await _client.get(uri, headers: _headers).timeout(_timeout);
    } on SocketException {
      throw FeedException(
        tr('No internet connection.'),
        transient: true,
        offline: true,
      );
    } catch (_) {
      throw FeedException(
        tr('Could not connect (timed out).'),
        transient: true,
      );
    }
    if (res.statusCode >= 400) {
      final transient = FeedException.isTransientStatus(res.statusCode);
      throw FeedException(
        switch (res.statusCode) {
          429 => 'Too many requests (429); will retry later.',
          404 || 410 => 'Feed not found (${res.statusCode}).',
          401 || 403 => 'Access denied (${res.statusCode}).',
          final s when s >= 500 => 'Server error ($s); will retry later.',
          final s => 'Server responded with $s.',
        },
        statusCode: res.statusCode,
        transient: transient,
        retryAfter: _retryAfter(res.headers['retry-after']),
      );
    }
    return _decode(res);
  }

  /// Retry-After in seconds (dates are rare for feeds), at most 8 s.
  static Duration? _retryAfter(String? header) {
    final seconds = int.tryParse(header?.trim() ?? '');
    if (seconds == null || seconds < 0) return null;
    return Duration(seconds: seconds.clamp(1, 8));
  }

  /// Decodes using the declared charset (UTF-8, Latin-1 or Arabic
  /// Windows-1256 / ISO-8859-6).
  static String _decode(http.Response res) =>
      decodeTextBody(res.bodyBytes, contentType: res.headers['content-type']);

  static String _decodeAmp(String s) => s.replaceAll('&amp;', '&');
}
