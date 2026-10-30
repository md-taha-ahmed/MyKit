/// How a feed has been doing across refreshes, so one-off hiccups (429,
/// server errors, timeouts) stay quiet and only feeds that keep failing are
/// reported.
class FeedHealth {
  const FeedHealth({
    this.failures = 0,
    this.failingSince,
    this.lastError,
    this.lastErrorTransient = true,
  });

  /// Refreshes in a row that failed.
  final int failures;

  /// When the current run of failures started.
  final DateTime? failingSince;
  final String? lastError;

  /// The last error was a rate limit / server / network kind.
  final bool lastErrorTransient;

  static const healthy = FeedHealth();

  /// Real errors (404, not a feed…) count after this long…
  static const _permanentGrace = Duration(days: 1);

  /// …temporary ones (429, 5xx, timeouts) only after this long.
  static const _transientGrace = Duration(days: 4);

  /// At least this many failed refreshes in a row, whatever the error.
  static const _minFailures = 3;

  bool get isFailing => failures > 0;

  /// Worth telling the user: failing every time for a while.
  bool isBroken(DateTime now) {
    final since = failingSince;
    if (failures < _minFailures || since == null) return false;
    return now.difference(since) >=
        (lastErrorTransient ? _transientGrace : _permanentGrace);
  }

  FeedHealth failed(String error, {required bool transient, DateTime? now}) =>
      FeedHealth(
        failures: failures + 1,
        failingSince: failingSince ?? now ?? DateTime.now(),
        lastError: error,
        lastErrorTransient: transient,
      );

  Map<String, dynamic> toJson() => {
    'failures': failures,
    'since': failingSince?.toIso8601String(),
    'error': lastError,
    'transient': lastErrorTransient,
  };

  static FeedHealth fromJson(Map<String, dynamic> j) => FeedHealth(
    failures: (j['failures'] as num?)?.toInt() ?? 0,
    failingSince: DateTime.tryParse(j['since'] as String? ?? ''),
    lastError: j['error'] as String?,
    lastErrorTransient: j['transient'] as bool? ?? true,
  );
}
