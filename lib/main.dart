import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/tools_registry.dart';
import 'core/i18n/i18n.dart';
import 'core/storage/app_directories.dart';
import 'core/storage/shared_preferences_provider.dart';
import 'core/tools/tools_provider.dart';
import 'features/setup/presentation/providers/setup_providers.dart';
import 'app/background_tasks.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Music: background playback + media notification / lock-screen controls.
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.mdtaha.mykit.music',
    androidNotificationChannelName: 'Music playback',
    androidNotificationOngoing: true,
  );
  // Movies & Series: libmpv video player.
  MediaKit.ensureInitialized();
  // Books: PDF engine (also used outside widgets to render covers).
  await pdfrxFlutterInitialize();
  // WorkManager: automatic Drive backups and checking followed sites.
  await initBackgroundTasks();
  final prefs = await SharedPreferences.getInstance();
  // Nothing saved yet: a fresh install, so open the setup checklist.
  final freshInstall = prefs.getKeys().isEmpty;
  // Dates in English and Arabic (the language is applied from settings).
  await I18n.init();
  final documents = await getApplicationDocumentsDirectory();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDocumentsDirectoryProvider.overrideWithValue(documents),
        toolsProvider.overrideWithValue(toolsRegistry),
        freshInstallProvider.overrideWithValue(freshInstall),
      ],
      child: const MyKitApp(),
    ),
  );
}
