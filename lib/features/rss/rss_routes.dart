import 'package:go_router/go_router.dart';

import 'presentation/screens/article_screen.dart';
import 'presentation/screens/feed_articles_screen.dart';
import 'presentation/screens/manage_feeds_screen.dart';
import 'presentation/screens/rss_home_screen.dart';

abstract final class RssRoutes {
  static const home = '/rss';
  static const manage = '/rss/manage';
  static String feed(String feedId) => '/rss/feed/$feedId';

  /// Article ids contain URLs, so they travel as an encoded query parameter.
  static String article(String articleId) =>
      Uri(path: '/rss/article', queryParameters: {'id': articleId}).toString();

  static final routes = <RouteBase>[
    GoRoute(
      path: home,
      builder: (context, state) => const RssHomeScreen(),
      routes: [
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
        ),
      ],
    ),
  ];
}
