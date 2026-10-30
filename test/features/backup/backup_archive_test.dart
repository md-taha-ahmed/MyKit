import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mykit/features/backup/data/datasources/backup_native_data_source.dart';
import 'package:mykit/features/backup/data/services/backup_archive.dart';
import 'package:mykit/features/backup/domain/entities/drive_backup.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeNative implements BackupNativeDataSource {
  Map<String, Object?> data = {
    'prefs': {
      'source_42': {
        'quality': ['s', '1080p'],
        'count': ['i', 3],
      },
    },
    'files': {
      'manga_extensions/eu.kanade.x.ext': Uint8List.fromList([1, 2, 3, 250]),
    },
  };
  Map<String, Object?>? imported;

  @override
  Future<Map<String, Object?>> export() async => data;

  @override
  Future<void> import(Map<String, Object?> data) async => imported = data;

  @override
  Future<void> restart() async {}
}

void main() {
  test('round-trips preferences with their types, and native data', () async {
    SharedPreferences.setMockInitialValues({
      'rss.feeds': '[{"url":"x"}]',
      'music.shuffle': true,
      'fitness.goal': 4,
      'movies.volume': 1.0,
      'manga.tags': ['a', 'b'],
      'google.oauth.refreshToken': 'old-device-token',
      'backup.lastHash': 'abc',
    });
    final prefs = await SharedPreferences.getInstance();
    final native = _FakeNative();
    final archive = BackupArchive(prefs, native);

    final built = await archive.build();

    // Simulate a fresh install that has only signed in again.
    await prefs.clear();
    await prefs.setString('google.oauth.refreshToken', 'new-device-token');
    await prefs.setString('leftover', 'gone after restore');

    final hash = await archive.restore(built.bytes);

    expect(hash, built.hash);
    expect(prefs.getString('rss.feeds'), '[{"url":"x"}]');
    expect(prefs.getBool('music.shuffle'), true);
    expect(prefs.getInt('fitness.goal'), 4);
    expect(prefs.getDouble('movies.volume'), 1.0);
    expect(prefs.getStringList('manga.tags'), ['a', 'b']);
    expect(prefs.getString('google.oauth.refreshToken'), 'new-device-token');
    expect(prefs.getString('leftover'), isNull);
    expect(prefs.getString('backup.lastHash'), isNull);

    final files = native.imported!['files'] as Map;
    expect(files['manga_extensions/eu.kanade.x.ext'], [1, 2, 3, 250]);
    expect(((native.imported!['prefs'] as Map)['source_42'] as Map)['count'], [
      'i',
      3,
    ]);
  });

  test('same data gives the same fingerprint', () async {
    SharedPreferences.setMockInitialValues({'b': 1, 'a': 'x'});
    final archive = BackupArchive(
      await SharedPreferences.getInstance(),
      _FakeNative(),
    );
    expect((await archive.build()).hash, (await archive.build()).hash);
  });

  test('rejects files that are not MyKit backups', () async {
    SharedPreferences.setMockInitialValues({'keep': 'me'});
    final prefs = await SharedPreferences.getInstance();
    final archive = BackupArchive(prefs, _FakeNative());
    await expectLater(
      archive.restore([1, 2, 3]),
      throwsA(isA<BackupException>()),
    );
    expect(prefs.getString('keep'), 'me');
  });
}
