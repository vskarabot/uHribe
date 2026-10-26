import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../models/hiking_route.dart';
import 'local/app_database.dart';
import 'routes_repository.dart';

class OfflineRoutesRepository {
  final RoutesRepository _routes;

  OfflineRoutesRepository(this._routes);

  static const _table = 'offline_routes';

  Future<void> downloadForPeak(int peakId) async {
    final routes = await _routes.fetchForPeak(peakId);
    await cacheForPeak(peakId, routes);
  }

  Future<void> cacheForPeak(int peakId, List<HikingRoute> routes) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final db = await AppDatabase.instance();

    final batch = db.batch();
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
