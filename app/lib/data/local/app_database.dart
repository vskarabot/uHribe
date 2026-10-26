import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  static const _fileName = 'uhribe.db';
  static const _version = 2;

  static Database? _db;
  static Future<Database>? _opening;

  static Future<Database> instance() {
    final db = _db;
    if (db != null) return Future.value(db);
    return _opening ??= _open().then((opened) {
      _db = opened;
      _opening = null;
      return opened;
    });
  }

  static Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), _fileName);
    return openDatabase(
      path,
      version: _version,
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
    );
  }

  static Future<void> _upgradeSchema(Database db, int from, int to) async {
    if (from < 2) await _createRoutesTable(db);
  }

  static Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      create table offline_peaks (
        id integer primary key,
        name text not null,
        name_alt text,
        elevation_m integer,
        lat real not null,
        lon real not null,
        wikipedia text,
        description text,
        mountain_area text,
        checkin_radius_m integer not null,
        downloaded_at text not null
      )
    ''');

    await _createRoutesTable(db);

    await db.execute('''
      create table pending_checkins (
        client_id text primary key,
        peak_id integer not null,
        peak_name text not null,
        lat real not null,
        lon real not null,
        accuracy_m real,
        distance_m real,
        device_time text not null,
        visited_on text not null,
        notes text,
        route_id integer,
        created_at text not null,
        attempts integer not null default 0,
        last_error text,
        -- Set when the server refused the check-in for a reason retrying
        -- can't fix. The row stays put so the user can see what happened
        -- and decide, rather than the ascent vanishing on its own.
        rejected integer not null default 0
      )
    ''');

    await db.execute(
      'create index pending_checkins_created_idx on pending_checkins (created_at)',
    );
  }

  static Future<void> _createRoutesTable(Database db) async {
    await db.execute('''
      create table offline_routes (
        peak_id integer not null,
        id integer not null,
        name text,
        ref text,
        from_name text,
        to_name text,
        difficulty text,
        distance_m integer,
        geojson text not null,
        downloaded_at text not null,
        primary key (peak_id, id)
      )
    ''');
  }
}
