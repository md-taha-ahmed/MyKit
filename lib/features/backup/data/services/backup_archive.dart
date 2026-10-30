import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/drive_backup.dart';
import '../datasources/backup_native_data_source.dart';

/// Packs everything MyKit keeps on the device into one gzipped JSON file and
/// writes it back:
///
/// * every Flutter preference (settings, libraries, progress, feeds…),
/// * the Android side: extension APKs, their trust keys and source settings.
///
/// Values are stored as `[tag, value]` so types survive JSON (`1.0` stays a
/// double). Imported book PDFs and caches are not included.
class BackupArchive {
  BackupArchive(this._prefs, this._native);

  final SharedPreferences _prefs;
  final BackupNativeDataSource _native;

  static const _format = 'mykit-backup';
  static const _version = 1;

  /// This install's Google sign-in and the backup bookkeeping stay local.
  static bool _isLocalOnly(String key) =>
      key.startsWith('google.oauth.refreshToken') ||
      key.startsWith('google.oauth.scopes') ||
      key.startsWith('backup.');

  /// The archive bytes and a fingerprint of their content (for "changed since
  /// the last backup?").
  Future<({Uint8List bytes, String hash})> build() async {
    final keys = _prefs.getKeys().where((k) => !_isLocalOnly(k)).toList()
      ..sort();
    final prefs = <String, Object>{
      for (final k in keys) k: ?_tag(_prefs.get(k)),
    };

    final native = await _native.export();
    final nativePrefs = (native['prefs'] as Map?) ?? const {};
    final nativeFiles = (native['files'] as Map?) ?? const {};
    final content = {
      'prefs': prefs,
      'native': {
        'prefs': _sorted(nativePrefs),
        'files': {
          for (final name in nativeFiles.keys.toList()..sort())
            name: base64Encode(nativeFiles[name] as Uint8List),
        },
      },
    };

    final body = jsonEncode(content);
    final doc = jsonEncode({
      'format': _format,
      'version': _version,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'content': content,
    });
    return (
      bytes: Uint8List.fromList(gzip.encode(utf8.encode(doc))),
      hash: _hash(body),
    );
  }

  /// Replaces the app's data with [bytes]' and returns its fingerprint. The
  /// app must restart afterwards so every tool reloads.
  Future<String> restore(List<int> bytes) async {
    final Map<String, dynamic> doc;
    try {
      doc = jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>;
    } catch (_) {
      throw const BackupException('This backup file is damaged.');
    }
    if (doc['format'] != _format) {
      throw const BackupException('Not a MyKit backup.');
    }
    if ((doc['version'] as num? ?? 0) > _version) {
      throw const BackupException('This backup is from a newer MyKit.');
    }
    // Decode everything before touching the current data.
    final content = doc['content'] as Map<String, dynamic>;
    final prefs = content['prefs'] as Map<String, dynamic>;
    final native = content['native'] as Map<String, dynamic>;
    final files = {
      for (final MapEntry(:key, :value)
          in (native['files'] as Map<String, dynamic>).entries)
        key: base64Decode(value as String),
    };

    for (final k in _prefs.getKeys().toList()) {
      if (!_isLocalOnly(k)) await _prefs.remove(k);
    }
    for (final MapEntry(:key, :value) in prefs.entries) {
      if (!_isLocalOnly(key)) await _put(key, value as List);
    }
    await _native.import({'prefs': native['prefs'], 'files': files});
    return _hash(jsonEncode(content));
  }

  Future<bool> _put(String key, List tagged) => switch (tagged) {
    ['s', final String v] => _prefs.setString(key, v),
    ['b', final bool v] => _prefs.setBool(key, v),
    ['i', final num v] => _prefs.setInt(key, v.toInt()),
    ['d', final num v] => _prefs.setDouble(key, v.toDouble()),
    ['ls', final List v] => _prefs.setStringList(key, v.cast<String>()),
    _ => Future.value(false),
  };

  static List<Object>? _tag(Object? v) => switch (v) {
    String() => ['s', v],
    bool() => ['b', v],
    int() => ['i', v],
    double() => ['d', v],
    List() => ['ls', v.cast<String>()],
    _ => null,
  };

  /// Maps with sorted keys, so the same data always hashes the same.
  static Object? _sorted(Object? v) => switch (v) {
    Map() => {
      for (final k in v.keys.map((k) => '$k').toList()..sort())
        k: _sorted(v[k]),
    },
    List() => [for (final x in v) _sorted(x)],
    _ => v,
  };

  static String _hash(String body) =>
      sha256.convert(utf8.encode(body)).toString();
}
