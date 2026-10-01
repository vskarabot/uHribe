import 'dart:async';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

/// Why a position couldn't be taken. Mapped to user-facing text by the caller,
/// which already has the strings for the map's locate button.
enum LocationFailure {
  servicesDisabled,
  permissionDenied,
  permissionDeniedForever,
  unavailable,
}

class LocationException implements Exception {
  final LocationFailure failure;
  const LocationException(this.failure);

  @override
  String toString() => 'LocationException(${failure.name})';
}

/// A settled position, agreed on by several consecutive fixes.
class SummitFix {
  final double lat;
  final double lon;
  final double? accuracyM;

  /// The OS's timestamp for the fix, not the app's clock. This is what gets
  /// sent to the server, so an offline check-in can still say *when* the user
  /// was standing there rather than when the phone found signal again.
  final DateTime timestamp;

  /// Android reports when a fix came from a mock provider. iOS has no
  /// equivalent, so false here means "not detected", not "genuine".
  final bool isMocked;

  const SummitFix({
    required this.lat,
    required this.lon,
    this.accuracyM,
    required this.timestamp,
    required this.isMocked,
  });
}

/// Takes GNSS fixes. Works with no network: the receiver computes the position
/// from the satellites themselves. A cold start is slower without the
/// network's assistance data, which is what [dwell] absorbs.
class LocationService {
  /// How long to keep sampling before settling for what we have.
  static const _dwell = Duration(seconds: 12);

  /// Stop early once the fix is this good and has been confirmed a few times
  /// — no reason to make someone stand in the wind for the full dwell.
  static const _goodAccuracyM = 15.0;
  static const _minSamples = 4;

  /// Takes a short burst of fixes rather than one.
  ///
  /// A single reading on a summit can be tens of metres out; a handful,
  /// filtered down to the ones that agree and then reduced to their median,
  /// is both more accurate and harder to forge convincingly than one
  /// synthetic coordinate.
  Future<SummitFix> acquireFix({Duration dwell = _dwell}) async {
    await ensurePermission();

    final samples = <Position>[];
    final settled = Completer<void>();
    StreamSubscription<Position>? sub;
    Timer? deadline;

    void finish() {
      if (!settled.isCompleted) settled.complete();
    }

    try {
      sub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
        ),
      ).listen(
        (position) {
          samples.add(position);
          if (samples.length >= _minSamples &&
              position.accuracy > 0 &&
              position.accuracy <= _goodAccuracyM) {
            finish();
          }
        },
        onError: (_) => finish(),
        cancelOnError: true,
      );

      deadline = Timer(dwell, finish);
      await settled.future;
    } finally {
      deadline?.cancel();
      await sub?.cancel();
    }

    if (samples.isEmpty) {
      // The stream gave us nothing in time — fall back to a single fix, which
      // may still come back from the OS's last known position.
      try {
        final single = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
        );
        samples.add(single);
      } catch (_) {
        throw const LocationException(LocationFailure.unavailable);
      }
    }

    return _consensus(samples);
  }

  /// Reduces the burst to one position: keep the samples whose accuracy is in
  /// the same league as the best one, then take their component-wise median so
  /// a single wild reading can't drag the result.
  SummitFix _consensus(List<Position> samples) {
    final ranked = [...samples]..sort((a, b) => a.accuracy.compareTo(b.accuracy));
    final best = ranked.first.accuracy;
    final cutoff = math.max(best * 2, best + 10);
    final kept = ranked.where((s) => s.accuracy <= cutoff).toList(growable: false);
    final use = kept.isEmpty ? ranked : kept;

    return SummitFix(
      lat: _median(use.map((s) => s.latitude).toList()),
      lon: _median(use.map((s) => s.longitude).toList()),
      accuracyM: best > 0 ? best : null,
      timestamp: ranked.first.timestamp,
      // One mocked sample taints the burst; a real receiver doesn't mix them.
      isMocked: samples.any((s) => s.isMocked),
    );
  }

  double _median(List<double> values) {
    values.sort();
    final mid = values.length ~/ 2;
    if (values.length.isOdd) return values[mid];
    return (values[mid - 1] + values[mid]) / 2;
  }

  /// Asks for location access if needed, throwing [LocationException] with the
  /// specific reason when it isn't available.
  Future<void> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException(LocationFailure.servicesDisabled);
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(LocationFailure.permissionDeniedForever);
    }
    if (permission == LocationPermission.denied) {
      throw const LocationException(LocationFailure.permissionDenied);
    }
  }

  /// Straight-line ground distance in metres.
  static double distanceM(double lat1, double lon1, double lat2, double lon2) =>
      Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
}
