import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/storage/shared_preferences_provider.dart';
import '../../domain/sahaba_models.dart';

final sahabaIndexProvider = FutureProvider<List<SahabaPerson>>((ref) async {
  final text = await rootBundle.loadString('assets/sahaba/index.txt');
  return SahabaPerson.parseIndex(text);
});

final sahabaPersonProvider =
    FutureProvider.family<Map<SahabaBook, List<SahabaChapter>>, String>((
      ref,
      id,
    ) async {
      final text = await rootBundle.loadString('assets/sahaba/$id.txt');
      return parseSahabaFile(text);
    });

/// Which chapter a person is on: `umar/riyad/12`.
String sahabaKey(String person, SahabaBook book, int index) =>
    '$person/${book.name}/$index';

class SahabaProgress {
  const SahabaProgress({this.read = const {}, this.last});

  final Set<String> read;

  /// The chapter opened last, for "continue".
  final String? last;
}

class SahabaProgressNotifier extends Notifier<SahabaProgress> {
  static const _readKey = 'sahaba.read';
  static const _lastKey = 'sahaba.last';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  SahabaProgress build() => SahabaProgress(
    read: (_prefs.getStringList(_readKey) ?? const []).toSet(),
    last: _prefs.getString(_lastKey),
  );

  Future<void> opened(String key) async {
    if (state.last == key) return;
    state = SahabaProgress(read: state.read, last: key);
    await _prefs.setString(_lastKey, key);
  }

  Future<void> markRead(String key) async {
    if (state.read.contains(key)) return;
    state = SahabaProgress(read: {...state.read, key}, last: state.last);
    await _prefs.setStringList(_readKey, state.read.toList());
  }

  double scroll(String key) => _prefs.getDouble('sahaba.scroll.$key') ?? 0;

  Future<void> saveScroll(String key, double offset) =>
      _prefs.setDouble('sahaba.scroll.$key', offset);
}

final sahabaProgressProvider =
    NotifierProvider<SahabaProgressNotifier, SahabaProgress>(
      SahabaProgressNotifier.new,
    );
