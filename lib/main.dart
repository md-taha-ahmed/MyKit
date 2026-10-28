import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/tools_registry.dart';
import 'core/storage/app_directories.dart';
import 'core/storage/shared_preferences_provider.dart';
import 'core/tools/tools_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Music: background playback + media notification / lock-screen controls.
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.mdtaha.mykit.music',
    androidNotificationChannelName: 'Music playback',
    androidNotificationOngoing: true,
  );
  // Books: PDF engine (also used outside widgets to render covers).
  await pdfrxFlutterInitialize();
  final prefs = await SharedPreferences.getInstance();
  final documents = await getApplicationDocumentsDirectory();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDocumentsDirectoryProvider.overrideWithValue(documents),
        toolsProvider.overrideWithValue(toolsRegistry),
      ],
      child: const MyKitApp(),
    ),
  );
}
