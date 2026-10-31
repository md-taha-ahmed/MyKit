import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/i18n/i18n.dart';
import '../features/backup/presentation/providers/backup_providers.dart';
import '../features/countdown/presentation/providers/countdown_providers.dart';
import '../features/setup/presentation/providers/setup_providers.dart';
import '../features/setup/setup_routes.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

class MyKitApp extends ConsumerStatefulWidget {
  const MyKitApp({super.key});

  @override
  ConsumerState<MyKitApp> createState() => _MyKitAppState();
}

class _MyKitAppState extends ConsumerState<MyKitApp> {
  StreamSubscription<Uri?>? _widgetLaunchSub;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _listenToHomeWidgetLaunches();
    // A fresh install starts with the setup checklist.
    if (ref.read(freshInstallProvider) && !ref.read(setupDoneProvider)) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(appRouterProvider).go(SetupRoutes.firstRun),
      );
    }
    // Google Drive backup: scheduled when the app is left, cancelled on return.
    final backup = ref.read(backupProvider.notifier);
    _lifecycle = AppLifecycleListener(
      onPause: backup.onLeave,
      onResume: backup.onReturn,
    );
  }

  /// Opens the right screen when the app is launched from a home-screen widget.
  void _listenToHomeWidgetLaunches() {
    final widgetService = ref.read(countdownHomeWidgetServiceProvider);
    final router = ref.read(appRouterProvider);

    void handle(Uri? uri) {
      final location = widgetService.locationForLaunchUri(uri);
      if (location != null) router.go(location);
    }

    widgetService.initialLaunchUri().then(handle);
    _widgetLaunchSub = widgetService.launchUris().listen(handle);
  }

  @override
  void dispose() {
    _widgetLaunchSub?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(appLanguageProvider);
    return MaterialApp.router(
      title: 'MyKit',
      // Arabic: right-to-left layout, Arabic dates and Material dialogs.
      locale: language.locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // A new subtree when the language changes, so every screen rebuilds
      // its text (the current route is kept).
      builder: (context, child) => KeyedSubtree(
        key: ValueKey(language.locale.languageCode),
        child: child ?? const SizedBox.shrink(),
      ),
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
