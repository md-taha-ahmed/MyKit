import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/i18n/i18n.dart';
import '../../../../core/google/google_oauth.dart';
import '../../domain/entities/feed_article.dart';
import '../../domain/entities/youtube_channel.dart';
import '../../domain/repositories/rss_repository.dart';

/// Reads the signed-in user's YouTube subscriptions (read-only) through the
/// YouTube Data API, authorised with [GoogleOAuth] (browser sign-in, so it
/// works without Google Play services).
class YoutubeSubscriptionsDataSource {
  YoutubeSubscriptionsDataSource(this._oauth, this._client);

  final GoogleOAuth _oauth;
  final http.Client _client;

  static const _scopes = ['https://www.googleapis.com/auth/youtube.readonly'];

  bool get isConfigured => _oauth.isConfigured;
  bool get isSignedIn => _oauth.isSignedIn;

  Future<void> configure(String clientId, String clientSecret) =>
      _oauth.saveClient(clientId, clientSecret);

  Future<void> disconnect() => _oauth.signOut();

  /// All subscriptions, A–Z. Opens the browser to sign in when needed.
  Future<List<YoutubeChannel>> fetchSubscriptions() async {
    try {
      return await _fetchAll(await _oauth.accessToken(_scopes));
    } on _Unauthorized {
      _oauth.invalidateAccessToken();
      return _fetchAll(await _oauth.accessToken(_scopes));
    } on GoogleOAuthException catch (e) {
      throw FeedException(e.message);
    }
  }

  Future<List<YoutubeChannel>> _fetchAll(String accessToken) async {
    final channels = <YoutubeChannel>[];
    String? pageToken;
    do {
      final uri = Uri.https('www.googleapis.com', '/youtube/v3/subscriptions', {
        'part': 'snippet',
        'mine': 'true',
        'maxResults': '50',
        'order': 'alphabetical',
        'pageToken': ?pageToken,
      });
      final res = await _client.get(
        uri,
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      if (res.statusCode == 401) throw const _Unauthorized();
      if (res.statusCode != 200) throw FeedException(_apiError(res));

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      for (final item in (body['items'] as List? ?? const [])) {
        final snippet = (item as Map<String, dynamic>)['snippet'] as Map;
        final id = (snippet['resourceId'] as Map?)?['channelId'] as String?;
        if (id == null) continue;
        final thumbs = snippet['thumbnails'] as Map? ?? const {};
        channels.add(
          YoutubeChannel(
            id: id,
            title: snippet['title'] as String? ?? id,
            description: snippet['description'] as String? ?? '',
            thumbnailUrl:
                ((thumbs['medium'] ?? thumbs['default']) as Map?)?['url']
                    as String?,
          ),
        );
      }
      pageToken = body['nextPageToken'] as String?;
    } while (pageToken != null);
    return channels;
  }

  /// A channel's latest uploads through the YouTube Data API: the fallback
  /// for when YouTube's RSS feeds are down. Never opens the browser; needs a
  /// previous sign-in. Ids match the RSS feed's (`yt:video:<id>`), so read /
  /// saved state carries over.
  Future<ParsedFeed> uploads(String channelId) async {
    if (!isConfigured || !isSignedIn) {
      throw FeedException(tr('Not signed in to YouTube.'));
    }
    try {
      return await _uploads(
        channelId,
        await _oauth.accessToken(_scopes, interactive: false),
      );
    } on _Unauthorized {
      _oauth.invalidateAccessToken();
      return _uploads(
        channelId,
        await _oauth.accessToken(_scopes, interactive: false),
      );
    } on GoogleOAuthException catch (e) {
      throw FeedException(e.message);
    }
  }

  Future<ParsedFeed> _uploads(String channelId, String accessToken) async {
    // Every channel's uploads playlist is its id with UC → UU.
    final playlist = channelId.startsWith('UC')
        ? 'UU${channelId.substring(2)}'
        : channelId;
    final uri = Uri.https('www.googleapis.com', '/youtube/v3/playlistItems', {
      'part': 'snippet,contentDetails',
      'playlistId': playlist,
      'maxResults': '15',
    });
    final res = await _client.get(
      uri,
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (res.statusCode == 401) throw const _Unauthorized();
    if (res.statusCode != 200) throw FeedException(_apiError(res));

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    var channelTitle = '';
    final articles = <FeedArticle>[];
    for (final item in (body['items'] as List? ?? const [])) {
      final map = item as Map<String, dynamic>;
      final snippet = map['snippet'] as Map? ?? const {};
      final details = map['contentDetails'] as Map? ?? const {};
      final videoId =
          details['videoId'] as String? ??
          (snippet['resourceId'] as Map?)?['videoId'] as String?;
      if (videoId == null) continue;
      channelTitle =
          snippet['videoOwnerChannelTitle'] as String? ??
          snippet['channelTitle'] as String? ??
          channelTitle;
      final thumbs = snippet['thumbnails'] as Map? ?? const {};
      final thumb =
          (thumbs['maxres'] ??
                  thumbs['standard'] ??
                  thumbs['high'] ??
                  thumbs['medium'] ??
                  thumbs['default'])
              as Map?;
      final description = (snippet['description'] as String? ?? '').trim();
      articles.add(
        FeedArticle(
          id: 'yt:video:$videoId',
          feedId: '',
          title: snippet['title'] as String? ?? 'Video',
          link: 'https://www.youtube.com/watch?v=$videoId',
          summary: description.length > 300
              ? '${description.substring(0, 300)}…'
              : description,
          content: description,
          imageUrl: thumb?['url'] as String?,
          author: channelTitle.isEmpty ? null : channelTitle,
          publishedAt: DateTime.tryParse(
            details['videoPublishedAt'] as String? ??
                snippet['publishedAt'] as String? ??
                '',
          ),
        ),
      );
    }
    return ParsedFeed(
      title: channelTitle.isEmpty ? channelId : channelTitle,
      siteUrl: 'https://www.youtube.com/channel/$channelId',
      articles: articles,
    );
  }

  static String _apiError(http.Response res) {
    try {
      final error = (jsonDecode(res.body) as Map)['error'] as Map;
      final reason = ((error['errors'] as List?)?.first as Map?)?['reason'];
      if (reason == 'accessNotConfigured' || reason == 'SERVICE_DISABLED') {
        return 'The YouTube Data API v3 is not enabled in your Google Cloud '
            'project.';
      }
      if (reason == 'quotaExceeded') {
        return 'YouTube API quota is used up for today. Try again tomorrow.';
      }
      return error['message'] as String? ?? 'YouTube error ${res.statusCode}';
    } catch (_) {
      return 'YouTube error ${res.statusCode}';
    }
  }
}

class _Unauthorized implements Exception {
  const _Unauthorized();
}
