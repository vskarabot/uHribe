import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/peak.dart';
import 'local/app_database.dart';

/// The peaks the user downloaded for a hike, cached on the device.
///
/// Small data — name, coordinates, elevation, radius — so a day's worth of
/// peaks is a few kilobytes. It's what lets the summit screen work with the
/// phone in airplane mode: GNSS gives the position without a network, and
/// this gives the target to compare it against.
class OfflinePeaksRepository {
  final SupabaseClient _client;

  OfflinePeaksRepository(this._client);

  static const _table = 'offline_peaks';

  /// Fetches [peakIds] from Supabase and stores them locally. Needs a network
  /// — this is the "before you leave the valley" step.
  Future<void> download(List<int> peakIds) async {
    if (peakIds.isEmpty) return;

    final rows = await _client.rpc(
      'peaks_for_offline',
      params: {'p_peak_ids': peakIds},
    ) as List;

    final peaks = rows.map((r) => Peak.fromJson(r as Map<String, dynamic>));
    final now = DateTime.now().toUtc().toIso8601String();
    final db = await AppDatabase.instance();

    final batch = db.batch();
    for (final peak in peaks) {
      batch.insert(
        _table,
        {
          'id': peak.id,
          'name': peak.name,
          'name_alt': peak.nameAlt,
          'elevation_m': peak.elevationM,
          'lat': peak.lat,
          'lon': peak.lon,
          'wikipedia': peak.wikipedia,
          'description': peak.description,
          'mountain_area': peak.mountainArea,
          'checkin_radius_m': peak.effectiveCheckinRadiusM,
          'downloaded_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Peak>> all() async {
    final db = await AppDatabase.instance();
    final rows = await db.query(_table, orderBy: 'name collate nocase');
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<Peak?> byId(int peakId) async {
    final db = await AppDatabase.instance();
    final rows = await db.query(_table, where: 'id = ?', whereArgs: [peakId], limit: 1);
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<void> remove(int peakId) async {
    final db = await AppDatabase.instance();
    await db.delete(_table, where: 'id = ?', whereArgs: [peakId]);
  }

  Peak _fromRow(Map<String, Object?> row) => Peak(
        id: (row['id'] as num).toInt(),
        name: row['name'] as String,
        nameAlt: row['name_alt'] as String?,
        elevationM: (row['elevation_m'] as num?)?.toInt(),
        lat: (row['lat'] as num).toDouble(),
        lon: (row['lon'] as num).toDouble(),
        wikipedia: row['wikipedia'] as String?,
        description: row['description'] as String?,
        mountainArea: row['mountain_area'] as String?,
        checkinRadiusM: (row['checkin_radius_m'] as num?)?.toInt(),
      );
}
