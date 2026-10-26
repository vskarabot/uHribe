import 'dart:async';
import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../data/pending_checkins_repository.dart';
import '../models/peak.dart';
import '../models/pending_checkin.dart';
import 'connectivity_service.dart';
import 'location_service.dart';

class _Err {
  static const tooFar = 'UH001';
  static const unknownPeak = 'UH002';
}

class MockedLocationException implements Exception {
  const MockedLocationException();

  @override
  String toString() => 'MockedLocationException';
}

class TooFarException implements Exception {
  final double distanceM;
  final double allowedM;
  const TooFarException(this.distanceM, this.allowedM);

  @override
  String toString() => 'TooFarException(${distanceM.round()}m > ${allowedM.round()}m)';
}

enum CheckInStatus {
  recorded,

  queued,

  rejected,
}

class CheckInOutcome {
  final CheckInStatus status;
  final double distanceM;
  final double? accuracyM;

  const CheckInOutcome({
    required this.status,
    required this.distanceM,
    this.accuracyM,
  });
}

enum _SyncResult { synced, rejected, retryLater }

class CheckInService {
  final SupabaseClient _client;
  final PendingCheckInsRepository _pending;
  final LocationService _location;
  final ConnectivityService _connectivity;
  final Uuid _uuid;

  CheckInService(
    this._client,
    this._pending,
    this._location,
    this._connectivity, {
    Uuid uuid = const Uuid(),
  }) : _uuid = uuid;

  Future<CheckInOutcome> checkIn({
    required Peak peak,
    DateTime? visitedOn,
    String? notes,
    int? routeId,
  }) async {
    final fix = await _location.acquireFix();

    if (fix.isMocked) {
      throw const MockedLocationException();
    }

    final distance = LocationService.distanceM(fix.lat, fix.lon, peak.lat, peak.lon);
    final allowed = allowedRadiusM(peak, fix.accuracyM);

    if (distance > allowed) {
      throw TooFarException(distance, allowed);
    }

    final checkIn = PendingCheckIn(
      clientId: _uuid.v4(),
      peakId: peak.id,
      peakName: peak.name,
      lat: fix.lat,
      lon: fix.lon,
      accuracyM: fix.accuracyM,
      distanceM: distance,
      deviceTime: fix.timestamp,
      visitedOn: visitedOn ?? DateTime.now(),
      notes: notes,
      routeId: routeId,
      createdAt: DateTime.now(),
    );

    await _pending.enqueue(checkIn);

    var status = CheckInStatus.queued;
    if (_connectivity.isOnline) {
      status = switch (await _sync(checkIn)) {
        _SyncResult.synced => CheckInStatus.recorded,
        _SyncResult.rejected => CheckInStatus.rejected,
        _SyncResult.retryLater => CheckInStatus.queued,
      };
    }

    return CheckInOutcome(
      status: status,
      distanceM: distance,
      accuracyM: fix.accuracyM,
    );
  }

  static double allowedRadiusM(Peak peak, double? accuracyM) {
    final radius = peak.effectiveCheckinRadiusM.toDouble();
    return radius + math.min(accuracyM ?? 0, radius);
  }

  Future<int> flushPending() async {
    final queued = await _pending.syncable();
    if (queued.isEmpty) return 0;

    var synced = 0;
    for (final checkIn in queued) {
      final result = await _sync(checkIn);
      if (result == _SyncResult.retryLater) break;
      if (result == _SyncResult.synced) synced++;
    }
    return synced;
  }

  Future<_SyncResult> _sync(PendingCheckIn checkIn) async {
    try {
      await _client.rpc('check_in_peak', params: checkIn.toRpcArgs());
      await _pending.remove(checkIn.clientId);
      return _SyncResult.synced;
    } on PostgrestException catch (e) {
      final permanent = e.code == _Err.tooFar ||
          e.code == _Err.unknownPeak ||
          (e.code?.startsWith('23') ?? false);

      if (permanent) {
        await _pending.recordFailure(checkIn.clientId, e.message, permanent: true);
        return _SyncResult.rejected;
      }

      await _pending.recordFailure(checkIn.clientId, e.message);
      return _SyncResult.retryLater;
    } catch (e) {
      await _pending.recordFailure(checkIn.clientId, e.toString());
      unawaited(_connectivity.refresh());
      return _SyncResult.retryLater;
    }
  }
}
