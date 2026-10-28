import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class CountdownLocalDataSource {
  CountdownLocalDataSource(this._prefs);

  static const _key = 'countdown.items.v1';

  final SharedPreferences _prefs;

  List<Map<String, dynamic>> readAll() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.cast<Map<String, dynamic>>();
  }

  Future<void> writeAll(List<Map<String, dynamic>> items) =>
      _prefs.setString(_key, jsonEncode(items));
}
