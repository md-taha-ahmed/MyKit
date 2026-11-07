import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/storage/shared_preferences_provider.dart';

class ReadingProgress {
  const ReadingProgress({this.read = const {}, this.last});

  final Set<String> read;

  /// The chapter opened last, for "continue".
  final String? last;
}

/// What's been read in a bundled collection, stored under [_prefix].
class ReadingProgressNotifier extends Notifier<ReadingProgress> {
  ReadingProgressNotifier(this._prefix);

  final String _prefix;

  String get _readKey => '$_prefix.read';
  String get _lastKey => '$_prefix.last';
  String _scrollKey(String key) => '$_prefix.scroll.$key';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  ReadingProgress build() => ReadingProgress(
    read: (_prefs.getStringList(_readKey) ?? const []).toSet(),
    last: _prefs.getString(_lastKey),
  );

  Future<void> opened(String key) async {
    if (state.last == key) return;
    state = ReadingProgress(read: state.read, last: key);
    await _prefs.setString(_lastKey, key);
  }

  Future<void> markRead(String key) async {
    if (state.read.contains(key)) return;
    state = ReadingProgress(read: {...state.read, key}, last: state.last);
    await _prefs.setStringList(_readKey, state.read.toList());
  }

  double scroll(String key) => _prefs.getDouble(_scrollKey(key)) ?? 0;

  Future<void> saveScroll(String key, double offset) =>
      _prefs.setDouble(_scrollKey(key), offset);
}
