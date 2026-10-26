import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../models/pending_checkin.dart';
import 'local/app_database.dart';

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

  Future<List<PendingCheckIn>> all() async {
    final db = await AppDatabase.instance();
    final rows = await db.query(_table, orderBy: 'created_at');
    return rows.map(PendingCheckIn.fromRow).toList(growable: false);
  }

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
