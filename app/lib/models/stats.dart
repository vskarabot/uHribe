class Stats {
  final int peaksVisited;
  final int totalVisits;
  final int visitsThisYear;

  final int totalElevationM;

  final String? highestPeakName;
  final int? highestPeakElevationM;
  final DateTime? firstVisitOn;
  final String? firstVisitPeakName;
  final DateTime? lastVisitOn;
  final String? lastVisitPeakName;

  const Stats({
    required this.peaksVisited,
    required this.totalVisits,
    this.visitsThisYear = 0,
    this.totalElevationM = 0,
    this.highestPeakName,
    this.highestPeakElevationM,
    this.firstVisitOn,
    this.firstVisitPeakName,
    this.lastVisitOn,
    this.lastVisitPeakName,
  });

  factory Stats.fromJson(Map<String, dynamic> json) {
    return Stats(
      peaksVisited: (json['peaks_visited'] as num?)?.toInt() ?? 0,
      totalVisits: (json['total_visits'] as num?)?.toInt() ?? 0,
      visitsThisYear: (json['visits_this_year'] as num?)?.toInt() ?? 0,
      totalElevationM: (json['total_elevation_m'] as num?)?.toInt() ?? 0,
      highestPeakName: json['highest_peak_name'] as String?,
      highestPeakElevationM: (json['highest_peak_elevation_m'] as num?)?.toInt(),
      firstVisitOn: _date(json['first_visit_on']),
      firstVisitPeakName: json['first_visit_peak_name'] as String?,
      lastVisitOn: _date(json['last_visit_on']),
      lastVisitPeakName: json['last_visit_peak_name'] as String?,
    );
  }

  static DateTime? _date(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  static const empty = Stats(peaksVisited: 0, totalVisits: 0);
}
