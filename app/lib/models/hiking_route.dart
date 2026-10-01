class HikingRoute {
  final int id;
  final String? name;
  final String? ref;
  final String? fromName;
  final String? toName;
  final String? difficulty;
  final int? distanceM;
  final String geojson; // GeoJSON geometry string (MultiLineString)

  const HikingRoute({
    required this.id,
    this.name,
    this.ref,
    this.fromName,
    this.toName,
    this.difficulty,
    this.distanceM,
    required this.geojson,
  });

  factory HikingRoute.fromJson(Map<String, dynamic> json) {
    return HikingRoute(
      id: json['id'] as int,
      name: json['name'] as String?,
      ref: json['ref'] as String?,
      fromName: json['from_name'] as String?,
      toName: json['to_name'] as String?,
      difficulty: json['difficulty'] as String?,
      distanceM: json['distance_m'] as int?,
      geojson: json['geojson'] as String,
    );
  }

  String get displayName {
    if (name != null && name!.isNotEmpty) return name!;
    if (ref != null && ref!.isNotEmpty) return ref!;
    if (fromName != null && toName != null) return '$fromName → $toName';
    return 'Pot #$id';
  }
}
