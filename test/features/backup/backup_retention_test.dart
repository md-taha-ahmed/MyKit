import 'package:flutter_test/flutter_test.dart';
import 'package:mykit/features/backup/domain/entities/drive_backup.dart';
import 'package:mykit/features/backup/domain/services/backup_retention.dart';

DriveBackup _at(DateTime t) => DriveBackup(
  id: t.toIso8601String(),
  name: 'mykit-backup-$t',
  createdAt: t,
  sizeBytes: 1,
);

void main() {
  final now = DateTime(2026, 10, 30, 18);

  test('a busy afternoon keeps only the 5 latest of today', () {
    final today = [
      for (var m = 0; m < 30; m++) _at(now.subtract(Duration(minutes: m * 5))),
    ];
    final keep = backupsToKeep(today, now);
    expect(keep, {for (final b in today.take(5)) b.id});
  });

  test('keeps the newest of each recent day and each recent week', () {
    final backups = [
      // Two a day for the last 60 days, at 09:00 and 21:00.
      for (var d = 0; d < 60; d++)
        for (final h in [21, 9]) _at(DateTime(2026, 10, 30 - d, h)),
    ].where((b) => b.createdAt.isBefore(now)).toList();

    final keep = backupsToKeep(backups, now);
    final kept = backups.where((b) => keep.contains(b.id)).toList();

    // Nothing older than 4 weeks.
    expect(kept.every((b) => now.difference(b.createdAt).inDays < 28), isTrue);
    // One per day for each of the last 7 days (today only has 09:00 yet).
    for (var d = 0; d < 7; d++) {
      final day = DateTime(2026, 10, 30 - d);
      expect(
        kept.any(
          (b) =>
              b.createdAt.year == day.year &&
              b.createdAt.month == day.month &&
              b.createdAt.day == day.day,
        ),
        isTrue,
        reason: 'day -$d',
      );
    }
    // 5 latest ∪ 7 days ∪ 4 weeks, with overlaps.
    expect(kept.length, lessThanOrEqualTo(16));
    expect(kept.length, greaterThanOrEqualTo(10));
  });

  test('keeps everything when there are only a few', () {
    final few = [_at(now), _at(now.subtract(const Duration(days: 40)))];
    expect(backupsToKeep(few, now), {for (final b in few) b.id});
  });
}
