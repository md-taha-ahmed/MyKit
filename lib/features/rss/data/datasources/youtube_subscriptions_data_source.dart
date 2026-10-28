import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/google/google_oauth.dart';
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
