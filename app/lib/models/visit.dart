class Visit {
  final String id;
  final String userId;
  final int peakId;
  final int? routeId;
  final DateTime visitedOn;
  final String? notes;
  final DateTime createdAt;

  final double? distanceM;

  final String? peakName;
  final int? peakElevationM;

  const Visit({
    required this.id,
    required this.userId,
    required this.peakId,
    this.routeId,
    required this.visitedOn,
    this.notes,
    required this.createdAt,
    this.distanceM,
    this.peakName,
    this.peakElevationM,
  });

  factory Visit.fromJson(Map<String, dynamic> json) {
    final peak = json['peaks'] as Map<String, dynamic>?;
    return Visit(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      peakId: json['peak_id'] as int,
      routeId: json['route_id'] as int?,
      visitedOn: DateTime.parse(json['visited_on'] as String),
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      distanceM: (json['distance_m'] as num?)?.toDouble(),
      peakName: peak?['name'] as String?,
      peakElevationM: peak?['elevation_m'] as int?,
    );
  }
}
