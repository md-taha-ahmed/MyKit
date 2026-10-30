import '../entities/drive_backup.dart';

/// Which backups to keep, so frequent automatic backups never push out the
/// ones you'd want to go back to:
///
/// * the [latest] newest,
/// * the newest of each of the last [days] days,
/// * the newest of each of the last [weeks] weeks (7-day blocks back from
///   [now]).
///
/// Returns the ids to keep; everything else can be deleted.
Set<String> backupsToKeep(
  List<DriveBackup> backups,
  DateTime now, {
  int latest = 5,
  int days = 7,
  int weeks = 4,
}) {
  final newestFirst = [...backups]
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final keep = {for (final b in newestFirst.take(latest)) b.id};

  // Calendar days in UTC, so a DST change never makes a day 23 hours.
  final today = DateTime.utc(now.year, now.month, now.day);
  final seenDays = <int>{};
  final seenWeeks = <int>{};
  for (final b in newestFirst) {
    final t = b.createdAt;
    final ageDays = today
        .difference(DateTime.utc(t.year, t.month, t.day))
        .inDays;
    if (ageDays < 0) continue; // clock skew: covered by `latest`
    if (ageDays < days && seenDays.add(ageDays)) keep.add(b.id);
    final week = ageDays ~/ 7;
    if (week < weeks && seenWeeks.add(week)) keep.add(b.id);
  }
  return keep;
}
