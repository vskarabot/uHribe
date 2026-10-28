import '../services/location_service.dart';
import 'peak.dart';

class NearbyFilter {
  final double lat;
  final double lon;

  const NearbyFilter({required this.lat, required this.lon});

  static const radiusM = 10000;

  double distanceM(Peak peak) => LocationService.distanceM(lat, lon, peak.lat, peak.lon);

  bool matches(Peak peak) => distanceM(peak) <= radiusM;
}
