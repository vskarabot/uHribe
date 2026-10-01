import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../models/hiking_route.dart';
import 'local/app_database.dart';
import 'routes_repository.dart';

/// The hiking routes belonging to downloaded peaks, cached on the device.
///
/// Bulkier than the peaks — a route carries its full geometry — but it's the
/// half that makes the peak sheet useful while walking: without it the
/// "Planinske poti" section has nothing to show exactly where the user is
/// standing in front of the fork.
class OfflineRoutesRepository {
  final RoutesRepository _routes;

  OfflineRoutesRepository(this._routes);

  static const _table = 'offline_routes';

  /// Fetches [peakId]'s routes from Supabase and stores them locally. Needs a
  /// network — this runs as part of downloading the peak itself.
  Future<void> downloadForPeak(int peakId) async {
    final routes = await _routes.fetchForPeak(peakId);
    await cacheForPeak(peakId, routes);
  }

  /// Stores [routes] as [peakId]'s cached set, replacing whatever was there.
  ///
  /// Also called opportunistically after a live fetch, so a peak downloaded
  /// before this cache existed — or one whose routes changed upstream — picks
  /// them up the first time its sheet is opened with a signal.
  Future<void> cacheForPeak(int peakId, List<HikingRoute> routes) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final db = await AppDatabase.instance();

    final batch = db.batch();
    // Routes that no longer belong to the peak have to go, and there's no
    // upsert that expresses "and delete the rest".
    batch.delete(_table, where: 'peak_id = ?', whereArgs: [peakId]);
    for (final route in routes) {
      batch.insert(
        _table,
        {
          'peak_id': peakId,
          'id': route.id,
          'name': route.name,
          'ref': route.ref,
          'from_name': route.fromName,
          'to_name': route.toName,
          'difficulty': route.difficulty,
          'distance_m': route.distanceM,
          'geojson': route.geojson,
          'downloaded_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<HikingRoute>> forPeak(int peakId) async {
    final db = await AppDatabase.instance();
    final rows = await db.query(
      _table,
      where: 'peak_id = ?',
      whereArgs: [peakId],
      orderBy: 'name collate nocase, id',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<void> removeForPeak(int peakId) async {
    final db = await AppDatabase.instance();
    await db.delete(_table, where: 'peak_id = ?', whereArgs: [peakId]);
  }

  HikingRoute _fromRow(Map<String, Object?> row) => HikingRoute(
        id: (row['id'] as num).toInt(),
        name: row['name'] as String?,
        ref: row['ref'] as String?,
        fromName: row['from_name'] as String?,
        toName: row['to_name'] as String?,
        difficulty: row['difficulty'] as String?,
        distanceM: (row['distance_m'] as num?)?.toInt(),
        geojson: row['geojson'] as String,
      );
}
