import 'dart:async';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

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

class SummitFix {
  final double lat;
  final double lon;
  final double? accuracyM;

  final DateTime timestamp;

  final bool isMocked;

  const SummitFix({
    required this.lat,
    required this.lon,
    this.accuracyM,
    required this.timestamp,
    required this.isMocked,
  });
}

class LocationService {
  static const _dwell = Duration(seconds: 12);

  static const _goodAccuracyM = 15.0;
  static const _minSamples = 4;

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
      isMocked: samples.any((s) => s.isMocked),
    );
  }

  double _median(List<double> values) {
    values.sort();
    final mid = values.length ~/ 2;
    if (values.length.isOdd) return values[mid];
    return (values[mid - 1] + values[mid]) / 2;
  }

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

  static double distanceM(double lat1, double lon1, double lat2, double lon2) =>
      Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
}
