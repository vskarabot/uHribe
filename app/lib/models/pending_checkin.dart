/// A check-in captured on a summit that hasn't reached the server yet.
///
/// Everything needed to verify it later is captured at the moment the user
/// taps, because by the time this syncs they may be at home, hours later and
/// kilometres away.
///
/// [clientId] is generated once, on the device. It's what makes replaying a
/// sync safe: if the insert succeeded but the response was lost, the server
/// recognises the id and returns the original row instead of duplicating it.
class PendingCheckIn {
  final String clientId;
  final int peakId;

  /// Denormalised so the pending list can be rendered offline, without
  /// needing the peak to still be in the local cache.
  final String peakName;

  final double lat;
  final double lon;
  final double? accuracyM;

  /// Distance to the summit as the device measured it. Advisory only — the
  /// server recomputes this from [lat]/[lon] and decides for itself.
  final double? distanceM;

  /// The OS's own timestamp for the fix, not `DateTime.now()`. Sent along so
  /// the server can see when the user was actually standing there.
  final DateTime deviceTime;

  final DateTime visitedOn;
  final String? notes;
  final int? routeId;
  final DateTime createdAt;
  final int attempts;
  final String? lastError;

  /// The server refused this one for a reason retrying won't fix (too far
  /// from the summit, unknown peak). It stays queued and visible so the user
  /// can decide what to do with it instead of it disappearing quietly.
  final bool rejected;

  const PendingCheckIn({
    required this.clientId,
    required this.peakId,
    required this.peakName,
    required this.lat,
    required this.lon,
    this.accuracyM,
    this.distanceM,
    required this.deviceTime,
    required this.visitedOn,
    this.notes,
    this.routeId,
    required this.createdAt,
    this.attempts = 0,
    this.lastError,
    this.rejected = false,
  });

  Map<String, Object?> toRow() => {
        'client_id': clientId,
        'peak_id': peakId,
        'peak_name': peakName,
        'lat': lat,
        'lon': lon,
        'accuracy_m': accuracyM,
        'distance_m': distanceM,
        'device_time': deviceTime.toUtc().toIso8601String(),
        'visited_on': dateOnly(visitedOn),
        'notes': notes,
        'route_id': routeId,
        'created_at': createdAt.toUtc().toIso8601String(),
        'attempts': attempts,
        'last_error': lastError,
        'rejected': rejected ? 1 : 0,
      };

  factory PendingCheckIn.fromRow(Map<String, Object?> row) {
    return PendingCheckIn(
      clientId: row['client_id'] as String,
      peakId: (row['peak_id'] as num).toInt(),
      peakName: row['peak_name'] as String,
      lat: (row['lat'] as num).toDouble(),
      lon: (row['lon'] as num).toDouble(),
      accuracyM: (row['accuracy_m'] as num?)?.toDouble(),
      distanceM: (row['distance_m'] as num?)?.toDouble(),
      deviceTime: DateTime.parse(row['device_time'] as String).toLocal(),
      visitedOn: DateTime.parse(row['visited_on'] as String),
      notes: row['notes'] as String?,
      routeId: (row['route_id'] as num?)?.toInt(),
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      attempts: (row['attempts'] as num?)?.toInt() ?? 0,
      lastError: row['last_error'] as String?,
      rejected: (row['rejected'] as num?)?.toInt() == 1,
    );
  }

  /// The arguments for `check_in_peak()`. `visited_on` is the user's *local*
  /// calendar date — a 22:00 summit in Slovenia belongs to that day, not to
  /// whatever day it is in UTC.
  Map<String, dynamic> toRpcArgs() => {
        'p_peak_id': peakId,
        'p_lat': lat,
        'p_lon': lon,
        'p_accuracy_m': accuracyM,
        'p_device_time': deviceTime.toUtc().toIso8601String(),
        'p_visited_on': dateOnly(visitedOn),
        'p_notes': notes,
        'p_route_id': routeId,
        'p_client_id': clientId,
      };

  /// A date with no time and no timezone, the way Postgres wants a `date`.
  static String dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
