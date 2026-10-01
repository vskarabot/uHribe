import 'dart:async';
import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../data/pending_checkins_repository.dart';
import '../models/peak.dart';
import '../models/pending_checkin.dart';
import 'connectivity_service.dart';
import 'location_service.dart';

/// Postgres error codes raised by `check_in_peak()`. UH003 (not
/// authenticated) is deliberately absent: it falls through to the retryable
/// branch, since a session that needs refreshing isn't a reason to throw away
/// someone's ascent.
class _Err {
  static const tooFar = 'UH001';
  static const unknownPeak = 'UH002';
}

/// Android told us the fix came from a mock-location app.
///
/// Checked here and only here: the flag comes from the device, so the server
/// has nothing independent to check it against. iOS reports nothing of the
/// kind, so a clean result means "not detected", not "genuine".
class MockedLocationException implements Exception {
  const MockedLocationException();

  @override
  String toString() => 'MockedLocationException';
}

/// The user was on the summit but not close enough. Carries the numbers so
/// the UI can say how far off they were instead of just refusing.
class TooFarException implements Exception {
  final double distanceM;
  final double allowedM;
  const TooFarException(this.distanceM, this.allowedM);

  @override
  String toString() => 'TooFarException(${distanceM.round()}m > ${allowedM.round()}m)';
}

enum CheckInStatus {
  /// Reached the server, which measured it and accepted it.
  recorded,

  /// Stored on the device; it'll sync when there's a network again.
  queued,

  /// The server refused it. Rare — the device applies the same radius before
  /// queueing — but the server measures on a spheroid where the device
  /// measures on a sphere, so a check-in right on the boundary can land
  /// differently. The row stays in the queue, flagged, for the user to see.
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

/// Turns "I'm standing on this summit" into a recorded visit — over the
/// network when there is one, and out of the device's queue when there isn't.
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

  /// Takes a fix and records a check-in for [peak].
  ///
  /// The check-in is written to the local queue *before* any network call, so
  /// a crash or a killed process between tapping and syncing can't lose an
  /// ascent. The generated client id makes the follow-up safe to replay: if
  /// the insert lands but the response doesn't, the retry returns the
  /// original row rather than a second one.
  ///
  /// Throws [LocationException] if there's no usable position and
  /// [TooFarException] if the fix isn't close enough to the summit.
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
      // The user's local calendar date — a 22:00 summit belongs to that day,
      // not to whatever day it already is in UTC.
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

  /// The radius the server will apply, mirrored here so the app can tell the
  /// user where they stand before they tap. Kept in step with
  /// `check_in_peak()` — a poor fix widens the radius, but only up to double.
  static double allowedRadiusM(Peak peak, double? accuracyM) {
    final radius = peak.effectiveCheckinRadiusM.toDouble();
    return radius + math.min(accuracyM ?? 0, radius);
  }

  /// Pushes everything queued. Returns how many rows made it.
  ///
  /// Stops at the first network failure instead of working through the rest:
  /// if one request couldn't reach the server, the next won't either, and
  /// there's no point burning battery on a ridge to find that out.
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
      // The server is the authority on distance, so its refusal stands even
      // though the device measured the same thing before queueing.
      final permanent = e.code == _Err.tooFar ||
          e.code == _Err.unknownPeak ||
          // Constraint violations — the request itself is malformed, and
          // repeating it verbatim can't help.
          (e.code?.startsWith('23') ?? false);

      if (permanent) {
        await _pending.recordFailure(checkIn.clientId, e.message, permanent: true);
        return _SyncResult.rejected;
      }

      // Anything else — a session that needs refreshing, a 5xx — is worth
      // another attempt later.
      await _pending.recordFailure(checkIn.clientId, e.message);
      return _SyncResult.retryLater;
    } catch (e) {
      // Socket errors, timeouts, DNS failures: the signal went away between
      // the connectivity probe and this request.
      await _pending.recordFailure(checkIn.clientId, e.toString());
      unawaited(_connectivity.refresh());
      return _SyncResult.retryLater;
    }
  }
}
