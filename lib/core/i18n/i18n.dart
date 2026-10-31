import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import '../storage/shared_preferences_provider.dart';
import 'ar.dart';

/// The app's language. Every tool's text goes through [tr]; Arabic also
/// lays the app out right to left and localizes dates and Material dialogs.
enum AppLanguage {
  system('System', 'النظام'),
  english('English', 'English'),
  arabic('العربية', 'العربية');

  const AppLanguage(this.label, this.arabicLabel);

  final String label;
  final String arabicLabel;

  bool get resolvesToArabic => switch (this) {
    AppLanguage.arabic => true,
    AppLanguage.english => false,
    AppLanguage.system =>
      ui.PlatformDispatcher.instance.locale.languageCode == 'ar',
  };

  Locale get locale =>
      resolvesToArabic ? const Locale('ar') : const Locale('en');
}

abstract final class I18n {
  static bool _arabic = false;

  static bool get isArabic => _arabic;

  /// Once in `main()`: date names for both languages.
  static Future<void> init() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ar');
  }

  static void apply(AppLanguage language) {
    _arabic = language.resolvesToArabic;
    Intl.defaultLocale = _arabic ? 'ar' : 'en';
  }
}

/// [text] in the app's language. `{name}` placeholders are filled from
/// [args] after translating, so the translation can move them around:
/// `tr('{count} unread', {'count': n})`.
String tr(String text, [Map<String, Object?> args = const {}]) {
  var out = I18n._arabic ? (arabicStrings[text] ?? text) : text;
  for (final MapEntry(:key, :value) in args.entries) {
    out = out.replaceAll('{$key}', '$value');
  }
  return out;
}

final appLanguageProvider = NotifierProvider<AppLanguageNotifier, AppLanguage>(
  AppLanguageNotifier.new,
);

class AppLanguageNotifier extends Notifier<AppLanguage> {
  static const _key = 'app.language';

  @override
  AppLanguage build() {
    final saved = ref.read(sharedPreferencesProvider).getString(_key);
    final language = AppLanguage.values.firstWhere(
      (l) => l.name == saved,
      orElse: () => AppLanguage.system,
    );
    I18n.apply(language);
    return language;
  }

  Future<void> set(AppLanguage language) async {
    I18n.apply(language);
    state = language;
    await ref.read(sharedPreferencesProvider).setString(_key, language.name);
  }
}
