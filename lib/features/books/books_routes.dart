import 'package:go_router/go_router.dart';

import 'presentation/screens/books_home_screen.dart';
import 'presentation/screens/reader_screen.dart';
import 'presentation/screens/shelves_screen.dart';

abstract final class BooksRoutes {
  static const home = '/books';
  static const shelves = '/books/shelves';
  static String reader(String bookId) => '/books/read/$bookId';

  static final routes = <RouteBase>[
    GoRoute(
      path: home,
      builder: (context, state) => const BooksHomeScreen(),
      routes: [
        GoRoute(
          path: 'shelves',
          builder: (context, state) => const ShelvesScreen(),
        ),
        GoRoute(
          path: 'read/:bookId',
          builder: (context, state) =>
              ReaderScreen(bookId: state.pathParameters['bookId']!),
        ),
      ],
    ),
  ];
}
