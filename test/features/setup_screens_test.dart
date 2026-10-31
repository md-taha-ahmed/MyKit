import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykit/core/ai/gemini_key_screen.dart';
import 'package:mykit/core/i18n/i18n.dart';
import 'package:mykit/core/storage/shared_preferences_provider.dart';
import 'package:mykit/features/setup/presentation/providers/setup_providers.dart';
import 'package:mykit/features/setup/presentation/screens/settings_screen.dart';
import 'package:mykit/features/setup/presentation/screens/setup_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FixedStatus extends SetupStatusNotifier {
  @override
  Future<SetupStatus> build() async =>
      const SetupStatus(notifications: true, ai: true);
}

Future<void> _pump(WidgetTester tester, Widget screen, AppLanguage lang) async {
  SharedPreferences.setMockInitialValues({'app.language': lang.name});
  final prefs = await SharedPreferences.getInstance();
  await I18n.init();
  tester.view.physicalSize = const Size(360, 780) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        setupStatusProvider.overrideWith(_FixedStatus.new),
      ],
      child: Consumer(
        builder: (context, ref, _) => MaterialApp(
          locale: ref.watch(appLanguageProvider).locale,
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: screen,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => I18n.apply(AppLanguage.english));

  for (final lang in [AppLanguage.english, AppLanguage.arabic]) {
    testWidgets('setup checklist lays out in ${lang.name}', (tester) async {
      await _pump(tester, const SetupScreen(firstRun: true), lang);
      expect(tester.takeException(), isNull);
      expect(
        find.text(
          lang == AppLanguage.arabic
              ? 'مرحباً بك في MyKit'
              : 'Welcome to MyKit',
        ),
        findsOneWidget,
      );
      final dir = Directionality.of(tester.element(find.byType(SetupScreen)));
      expect(
        dir,
        lang == AppLanguage.arabic ? TextDirection.rtl : TextDirection.ltr,
      );
      // Scroll to the end: every card must fit.
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('settings and Gemini key screens lay out in ${lang.name}', (
      tester,
    ) async {
      await _pump(tester, const SettingsScreen(), lang);
      expect(tester.takeException(), isNull);
      await _pump(tester, const GeminiKeyScreen(), lang);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('switching the language rebuilds the text', (tester) async {
    await _pump(tester, const SettingsScreen(), AppLanguage.english);
    expect(find.text('Settings'), findsOneWidget);
    await tester.tap(find.text('العربية'));
    await tester.pumpAndSettle();
    expect(find.text('الإعدادات'), findsOneWidget);
  });
}
