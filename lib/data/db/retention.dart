/// How long CellMeter keeps each kind of record.
///
/// Raw samples are by far the bulk of the database and the least useful once
/// the sessions have been derived from them, so they age out first. Sessions
/// and capacity estimates are small and are the entire point of the app's
/// long-term view, so they are kept far longer.
class RetentionPolicy {
  const RetentionPolicy({
    this.rawSamples = const Duration(days: 30),
    this.sessions = const Duration(days: 365),
    this.appUsage = const Duration(days: 90),
    this.capacityEstimates = const Duration(days: 1095),
  });

  final Duration rawSamples;
  final Duration sessions;
  final Duration appUsage;
  final Duration capacityEstimates;

  /// The free tier shows a day of history, matching what competitors offer,
  /// while still recording everything so an upgrade reveals the full past
  /// rather than starting from zero.
  static const free = RetentionPolicy();

  static const pro = RetentionPolicy(
    rawSamples: Duration(days: 90),
    sessions: Duration(days: 1095),
    appUsage: Duration(days: 365),
  );
}
