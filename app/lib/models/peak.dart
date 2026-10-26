class Peak {
  final int id;
  final String name;
  final String? nameAlt;
  final int? elevationM;
  final double lat;
  final double lon;
  final String? wikipedia;
  final String? description;
  final String? mountainArea;

  final int? checkinRadiusM;

  static const defaultCheckinRadiusM = 50;

  const Peak({
    required this.id,
    required this.name,
    this.nameAlt,
    this.elevationM,
    required this.lat,
    required this.lon,
    this.wikipedia,
    this.description,
    this.mountainArea,
    this.checkinRadiusM,
  });

  int get effectiveCheckinRadiusM => checkinRadiusM ?? defaultCheckinRadiusM;

  factory Peak.fromJson(Map<String, dynamic> json) {
    return Peak(
      id: json['id'] as int,
      name: json['name'] as String,
      nameAlt: json['name_alt'] as String?,
      elevationM: json['elevation_m'] as int?,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      wikipedia: json['wikipedia'] as String?,
      description: json['description'] as String?,
      mountainArea: json['mountain_area'] as String?,
      checkinRadiusM: (json['checkin_radius_m'] as num?)?.toInt(),
    );
  }
}
