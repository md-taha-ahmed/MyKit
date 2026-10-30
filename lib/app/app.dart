import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/backup/presentation/providers/backup_providers.dart';
import '../features/countdown/presentation/providers/countdown_providers.dart';
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
    return MaterialApp.router(
      title: 'MyKit',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
