import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mykit/core/storage/shared_preferences_provider.dart';
import 'package:mykit/features/rise_fall/domain/story_models.dart';
import 'package:mykit/features/rise_fall/presentation/providers/rise_fall_providers.dart';
import 'package:mykit/features/rise_fall/rise_fall_routes.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final stories = [
    for (final id in storyCountryIds)
      StoryCountry.parse(
        id,
        File('assets/rise_fall/$id.txt').readAsStringSync(),
      ),
  ];

  // Opens one route with the real stories; a layout error fails the test.
  Future<void> open(WidgetTester tester, String path) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          storiesProvider.overrideWith((ref) async => stories),
        ],
        child: MaterialApp.router(
          theme: ThemeData.dark(),
          routerConfig: GoRouter(
            initialLocation: path,
            routes: RiseFallRoutes.routes,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets('home lists every country in its group', (tester) async {
    await open(tester, RiseFallRoutes.home);
    expect(find.text('سقوط ونهوض'), findsOneWidget);
    expect(find.text('ألمانيا'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('اليمن'), 300);
    expect(find.text('اليمن'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sources line up by their language', (tester) async {
    await open(tester, RiseFallRoutes.country('south_korea'));
    final arabic = find.textContaining('ويكيبيديا)');
    await tester.scrollUntilVisible(arabic, 300);
    expect(Directionality.of(tester.element(arabic)), TextDirection.rtl);
    final english = find.text('History of South Korea (Wikipedia)');
    expect(Directionality.of(tester.element(english)), TextDirection.ltr);
  });

  testWidgets('a country shows its parts and sources', (tester) async {
    await open(tester, RiseFallRoutes.country('yemen'));
    expect(find.text('اليمن'), findsOneWidget);
    expect(find.text(stories.last.parts.first.title), findsOneWidget);
    await tester.scrollUntilVisible(find.text('مراجع للتحقق والاستزادة'), 400);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every part of every country opens', (tester) async {
    for (final c in stories) {
      for (final p in c.parts) {
        await open(tester, RiseFallRoutes.part(c.id, p.index));
        expect(
          find.text(p.title),
          findsOneWidget,
          reason: '${c.id} ${p.index}',
        );
      }
    }
  });

  testWidgets('finishing a part marks it read and moves to the next', (
    tester,
  ) async {
    await open(tester, RiseFallRoutes.part('germany', 0));
    final next = find.text('انتهيت، الجزء التالي');
    await tester.scrollUntilVisible(
      next,
      600,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text(stories.first.parts[1].title), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('patterns and compare open', (tester) async {
    await open(tester, RiseFallRoutes.patterns);
    expect(find.text(StoryPattern.war.label), findsOneWidget);
    await open(tester, RiseFallRoutes.pattern(StoryPattern.corruption.name));
    expect(find.text(StoryPattern.corruption.label), findsOneWidget);
    await open(tester, RiseFallRoutes.compare);
    expect(find.text('قارن دولتين'), findsOneWidget);
    expect(find.text(StoryPattern.war.label), findsOneWidget);
  });
}
