import 'package:flutter_test/flutter_test.dart';
import 'package:uhribe/models/peak.dart';
import 'package:uhribe/models/pending_checkin.dart';
import 'package:uhribe/models/visit.dart';
import 'package:uhribe/services/checkin_service.dart';

const _triglav = Peak(
  id: 174875,
  name: 'Triglav',
  elevationM: 2864,
  lat: 46.3786,
  lon: 13.8353,
);

PendingCheckIn _sample({String? notes}) => PendingCheckIn(
      clientId: '3f1a0c6e-1111-4222-8333-444455556666',
      peakId: 174875,
      peakName: 'Triglav',
      lat: 46.37861,
      lon: 13.83529,
      accuracyM: 8.5,
      distanceM: 12.3,
      deviceTime: DateTime.utc(2026, 7, 14, 9, 41, 30),
      visitedOn: DateTime(2026, 7, 14),
      notes: notes,
      createdAt: DateTime.utc(2026, 7, 14, 9, 41, 35),
    );

void main() {
  group('check-in radius', () {
    test('uses the app-wide default when the peak has no override', () {
      expect(_triglav.effectiveCheckinRadiusM, Peak.defaultCheckinRadiusM);
      expect(CheckInService.allowedRadiusM(_triglav, null), 50);
    });

    test('respects a per-peak override', () {
      const broad = Peak(id: 1, name: 'Plateau', lat: 46, lon: 14, checkinRadiusM: 200);
      expect(CheckInService.allowedRadiusM(broad, null), 200);
    });

    test('a poor fix widens the radius', () {
      expect(CheckInService.allowedRadiusM(_triglav, 30), 80);
    });

    test('but never by more than double, so a claimed huge accuracy is useless', () {
      expect(CheckInService.allowedRadiusM(_triglav, 10000), 100);
    });
  });

  group('PendingCheckIn', () {
    test('survives a round trip through the local database', () {
      final original = _sample(notes: 'megleno');
      final restored = PendingCheckIn.fromRow(original.toRow());

      expect(restored.clientId, original.clientId);
      expect(restored.peakId, original.peakId);
      expect(restored.peakName, original.peakName);
      expect(restored.lat, closeTo(original.lat, 1e-9));
      expect(restored.lon, closeTo(original.lon, 1e-9));
      expect(restored.accuracyM, closeTo(8.5, 1e-9));
      expect(restored.distanceM, closeTo(12.3, 1e-9));
      expect(restored.deviceTime.toUtc(), original.deviceTime.toUtc());
      expect(restored.notes, 'megleno');
      expect(restored.rejected, isFalse);
    });

    test('sends the client id so a replayed sync cannot duplicate the visit', () {
      final args = _sample().toRpcArgs();
      expect(args['p_client_id'], '3f1a0c6e-1111-4222-8333-444455556666');
    });

    test('sends the device time, not the sync time', () {
      final args = _sample().toRpcArgs();
      expect(args['p_device_time'], '2026-07-14T09:41:30.000Z');
    });

    test('sends the local calendar date, so a late summit keeps its day', () {
      // 22:30 local on the 14th is already the 15th in UTC; the ascent still
      // belongs to the 14th.
      final lateEvening = PendingCheckIn(
        clientId: 'c',
        peakId: 1,
        peakName: 'Šmarna gora',
        lat: 46.2,
        lon: 14.4,
        deviceTime: DateTime(2026, 7, 14, 22, 30),
        visitedOn: DateTime(2026, 7, 14, 22, 30),
        createdAt: DateTime(2026, 7, 14, 22, 30),
      );
      expect(lateEvening.toRpcArgs()['p_visited_on'], '2026-07-14');
    });
  });

  group('Visit', () {
    test('reads how far from the summit the check-in was taken', () {
      final visit = Visit.fromJson({
        'id': 'v1',
        'user_id': 'u1',
        'peak_id': 174875,
        'visited_on': '2026-07-14',
        'created_at': '2026-07-14T20:00:00Z',
        'distance_m': 12.3,
      });

      expect(visit.distanceM, closeTo(12.3, 1e-9));
    });

    test('tolerates a row predating the check-in columns', () {
      final visit = Visit.fromJson({
        'id': 'v1',
        'user_id': 'u1',
        'peak_id': 174875,
        'visited_on': '2009-08-01',
        'created_at': '2026-07-14T20:00:00Z',
      });

      expect(visit.distanceM, isNull);
    });
  });
}
