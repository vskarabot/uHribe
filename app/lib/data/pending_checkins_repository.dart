import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../models/pending_checkin.dart';
import 'local/app_database.dart';

/// The queue of check-ins waiting for a network.
///
/// Rows only leave this table once the server has accepted them (or has
/// rejected them for a reason retrying won't fix), so losing signal for a day
/// costs nothing.
class PendingCheckInsRepository {
  static const _table = 'pending_checkins';

  Future<void> enqueue(PendingCheckIn checkIn) async {
    final db = await AppDatabase.instance();
    await db.insert(
      _table,
      checkIn.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Oldest first, so a backlog syncs in the order it was climbed.
  Future<List<PendingCheckIn>> all() async {
    final db = await AppDatabase.instance();
    final rows = await db.query(_table, orderBy: 'created_at');
    return rows.map(PendingCheckIn.fromRow).toList(growable: false);
  }

  /// The ones a sync should actually attempt — everything except those the
  /// server has already refused for good.
  Future<List<PendingCheckIn>> syncable() async {
    final db = await AppDatabase.instance();
    final rows = await db.query(
      _table,
      where: 'rejected = 0',
      orderBy: 'created_at',
    );
    return rows.map(PendingCheckIn.fromRow).toList(growable: false);
  }

  Future<void> remove(String clientId) async {
    final db = await AppDatabase.instance();
    await db.delete(_table, where: 'client_id = ?', whereArgs: [clientId]);
  }

  /// Records why a sync attempt failed, for the pending list to show. The row
  /// stays queued; only [remove] takes it out.
  ///
  /// [permanent] marks it as refused rather than merely unlucky, so later
  /// syncs skip it instead of hammering the server with a request that will
  /// never succeed.
  Future<void> recordFailure(
    String clientId,
    String error, {
    bool permanent = false,
  }) async {
    final db = await AppDatabase.instance();
    await db.rawUpdate(
      'update $_table set attempts = attempts + 1, last_error = ?, rejected = ? '
      'where client_id = ?',
      [error, permanent ? 1 : 0, clientId],
    );
  }
}
