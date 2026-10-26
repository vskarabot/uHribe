class PendingCheckIn {
  final String clientId;
  final int peakId;

  final String peakName;

  final double lat;
  final double lon;
  final double? accuracyM;

  final double? distanceM;

  final DateTime deviceTime;

  final DateTime visitedOn;
  final String? notes;
  final int? routeId;
  final DateTime createdAt;
  final int attempts;
  final String? lastError;

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

  static String dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
