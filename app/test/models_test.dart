import 'package:flutter_test/flutter_test.dart';
import 'package:uhribe/models/hiking_route.dart';
import 'package:uhribe/models/peak.dart';
import 'package:uhribe/models/profile.dart';
import 'package:uhribe/models/stats.dart';
import 'package:uhribe/models/visit.dart';

void main() {
  group('Peak.fromJson', () {
    test('parses a full row', () {
      final peak = Peak.fromJson({
        'id': 174875,
        'name': 'Triglav',
        'name_alt': null,
        'elevation_m': 2864,
        'lat': 46.3786,
        'lon': 13.8353,
        'wikipedia': 'sl:Triglav',
        'description': 'Najvišji vrh Slovenije.',
      });

      expect(peak.id, 174875);
      expect(peak.name, 'Triglav');
      expect(peak.elevationM, 2864);
      expect(peak.lat, closeTo(46.3786, 1e-9));
      expect(peak.lon, closeTo(13.8353, 1e-9));
      expect(peak.wikipedia, 'sl:Triglav');
    });

    test('handles a null elevation and missing optional fields', () {
      final peak = Peak.fromJson({
        'id': 1,
        'name': 'Neznani hrib',
        'lat': 46.0,
        'lon': 14.0,
      });

      expect(peak.elevationM, isNull);
      expect(peak.nameAlt, isNull);
      expect(peak.wikipedia, isNull);
    });
  });

  group('HikingRoute', () {
    test('fromJson parses and displayName prefers name', () {
      final route = HikingRoute.fromJson({
        'id': 1,
        'name': 'Pot na Triglav',
        'ref': 'PP1',
        'from_name': 'Rudno polje',
        'to_name': 'Triglav',
        'difficulty': 'demanding_mountain_hiking',
        'distance_m': 8500,
        'geojson': '{"type":"MultiLineString","coordinates":[]}',
      });

      expect(route.displayName, 'Pot na Triglav');
      expect(route.distanceM, 8500);
    });

    test('displayName falls back to ref, then from/to, then id', () {
      final withRef = HikingRoute.fromJson({
        'id': 2,
        'ref': 'PP1',
        'geojson': '{}',
      });
      expect(withRef.displayName, 'PP1');

      final withFromTo = HikingRoute.fromJson({
        'id': 3,
        'from_name': 'A',
        'to_name': 'B',
        'geojson': '{}',
      });
      expect(withFromTo.displayName, 'A → B');

      final bare = HikingRoute.fromJson({'id': 4, 'geojson': '{}'});
      expect(bare.displayName, 'Pot #4');
    });
  });

  group('Visit.fromJson', () {
    test('parses a joined row with peak info', () {
      final visit = Visit.fromJson({
        'id': 'abc-123',
        'user_id': 'user-1',
        'peak_id': 174875,
        'route_id': null,
        'visited_on': '2025-08-15',
        'notes': 'Lep razgled.',
        'created_at': '2025-08-15T10:00:00Z',
        'peaks': {'name': 'Triglav', 'elevation_m': 2864},
      });

      expect(visit.peakName, 'Triglav');
      expect(visit.peakElevationM, 2864);
      expect(visit.visitedOn, DateTime.parse('2025-08-15'));
    });
  });

  group('Stats.fromJson', () {
    test('parses counts and falls back sensibly', () {
      final stats = Stats.fromJson({
        'peaks_visited': 5,
        'total_visits': 7,
        'highest_peak_name': 'Triglav',
        'highest_peak_elevation_m': 2864,
      });
      expect(stats.peaksVisited, 5);
      expect(stats.totalVisits, 7);
    });

    test('Stats.empty has zero counts', () {
      expect(Stats.empty.peaksVisited, 0);
      expect(Stats.empty.totalVisits, 0);
    });
  });

  group('Profile', () {
    test('copyWith only overrides given fields', () {
      const profile = Profile(
        id: 'u1',
        email: 'a@b.com',
        displayName: 'Ana',
        homeRegion: 'Gorenjska',
      );
      final updated = profile.copyWith(displayName: 'Ana Novak');

      expect(updated.displayName, 'Ana Novak');
      expect(updated.homeRegion, 'Gorenjska');
      expect(updated.email, 'a@b.com');
    });
  });
}
