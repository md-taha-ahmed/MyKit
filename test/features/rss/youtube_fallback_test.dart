import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mykit/core/google/google_oauth.dart';
import 'package:mykit/features/rss/data/datasources/youtube_subscriptions_data_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('uploads come from the channel uploads playlist with RSS ids', () async {
    SharedPreferences.setMockInitialValues({
      'google.oauth.clientId': 'id',
      'google.oauth.clientSecret': 'secret',
      'google.oauth.refreshToken': 'refresh',
    });
    final prefs = await SharedPreferences.getInstance();
    final requests = <Uri>[];
    final client = MockClient((req) async {
      requests.add(req.url);
      if (req.url.host == 'oauth2.googleapis.com') {
        return http.Response(
          jsonEncode({'access_token': 'token', 'expires_in': 3600}),
          200,
        );
      }
      expect(req.headers['Authorization'], 'Bearer token');
      return http.Response(
        jsonEncode({
          'items': [
            {
              'snippet': {
                'title': 'New video',
                'description': 'About it',
                'channelTitle': 'Chan',
                'publishedAt': '2026-10-28T10:00:00Z',
                'thumbnails': {
                  'high': {'url': 'https://i.ytimg.com/vi/abc/hqdefault.jpg'},
                },
              },
              'contentDetails': {
                'videoId': 'abc',
                'videoPublishedAt': '2026-10-28T09:00:00Z',
              },
            },
          ],
        }),
        200,
      );
    });

    final source = YoutubeSubscriptionsDataSource(
      GoogleOAuth(prefs, client),
      client,
    );
    final feed = await source.uploads('UCabc123');

    final api = requests.last;
    expect(api.path, '/youtube/v3/playlistItems');
    expect(api.queryParameters['playlistId'], 'UUabc123');
    final video = feed.articles.single;
    expect(video.id, 'yt:video:abc');
    expect(video.link, 'https://www.youtube.com/watch?v=abc');
    expect(video.author, 'Chan');
    expect(video.publishedAt, DateTime.utc(2026, 10, 28, 9));
    expect(feed.title, 'Chan');
  });
}
