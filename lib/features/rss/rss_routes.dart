import 'package:go_router/go_router.dart';

import 'presentation/screens/article_chat_screen.dart';
import 'presentation/screens/article_screen.dart';
import 'presentation/screens/feed_articles_screen.dart';
import 'presentation/screens/manage_feeds_screen.dart';
import 'presentation/screens/rss_home_screen.dart';
import 'presentation/screens/rss_scroll_screen.dart';
import 'presentation/screens/shorts_screen.dart';
import 'presentation/screens/youtube_import_screen.dart';

abstract final class RssRoutes {
  static const home = '/rss';
  static const manage = '/rss/manage';
  static const youtubeImport = '/rss/youtube-import';
  static String feed(String feedId) => '/rss/feed/$feedId';

  /// Full-screen brief view of what's selected (a category, a feed or all).
  static String scroll({String? categoryId, String? feedId}) => Uri(
    path: '/rss/scroll',
    queryParameters: {'category': ?categoryId, 'feed': ?feedId},
  ).toString();

  /// Full-screen YouTube Shorts player (optionally starting at one Short).
  static String shorts({String? startId, String? categoryId, String? feedId}) =>
      Uri(
        path: '/rss/shorts',
        queryParameters: {
          'start': ?startId,
          'category': ?categoryId,
          'feed': ?feedId,
        },
      ).toString();

  /// Article ids contain URLs, so they travel as an encoded query parameter.
  static String article(String articleId) =>
      Uri(path: '/rss/article', queryParameters: {'id': articleId}).toString();

  /// Chat with Gemini about an article.
  static String articleChat(String articleId) => Uri(
    path: '/rss/article/chat',
    queryParameters: {'id': articleId},
  ).toString();

  static final routes = <RouteBase>[
    GoRoute(
      path: home,
      builder: (context, state) => const RssHomeScreen(),
      routes: [
        GoRoute(
          path: 'scroll',
          builder: (context, state) => RssScrollScreen(
            categoryId: state.uri.queryParameters['category'],
            feedId: state.uri.queryParameters['feed'],
          ),
        ),
        GoRoute(
          path: 'shorts',
          builder: (context, state) => ShortsScreen(
            startId: state.uri.queryParameters['start'],
            categoryId: state.uri.queryParameters['category'],
            feedId: state.uri.queryParameters['feed'],
          ),
        ),
        GoRoute(
          path: 'youtube-import',
          builder: (context, state) => const YoutubeImportScreen(),
        ),
        GoRoute(
          path: 'manage',
          builder: (context, state) => const ManageFeedsScreen(),
        ),
        GoRoute(
          path: 'feed/:feedId',
          builder: (context, state) =>
              FeedArticlesScreen(feedId: state.pathParameters['feedId']!),
        ),
        GoRoute(
          path: 'article',
          builder: (context, state) =>
              ArticleScreen(articleId: state.uri.queryParameters['id'] ?? ''),
          routes: [
            GoRoute(
              path: 'chat',
              builder: (context, state) => ArticleChatScreen(
                articleId: state.uri.queryParameters['id'] ?? '',
              ),
            ),
          ],
        ),
      ],
    ),
  ];
}
