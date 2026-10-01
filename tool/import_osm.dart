// Imports Slovenian peaks and hiking routes from OpenStreetMap (via the
// Overpass API) into Supabase.
//
// Usage:
//   cd tool
//   dart pub get
//   cp .env.example .env   # fill in SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY
//   dart run import_osm.dart
//
// Safe to re-run: everything is upserted by OSM id, so running it again just
// refreshes the data.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';

const _overpassMirrors = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.kumi.systems/api/interpreter',
  'https://overpass.openstreetmap.ru/api/interpreter',
];
const _retryDelays = [Duration(seconds: 5), Duration(seconds: 15), Duration(seconds: 45)];
const _retryableStatusCodes = {429, 503, 504};
/// Client-side cap on one Overpass request. Comfortably longer than the
/// server's own [timeout:180], so a mirror that is merely slow still gets to
/// answer, while one that has gone silent is given up on.
const _requestTimeout = Duration(seconds: 240);
const _batchSize = 500;

Future<void> main() async {
  final env = _loadEnv('.env');
  if (env == null) {
    stderr.writeln('No .env in ${Directory.current.path}. '
        'Run this from the tool/ directory: cp .env.example .env, then fill it in.');
    exit(1);
  }

  final supabaseUrl = env['SUPABASE_URL'] ?? '';
  final serviceRoleKey = env['SUPABASE_SERVICE_ROLE_KEY'] ?? '';
  final missing = [
    if (supabaseUrl.isEmpty) 'SUPABASE_URL',
    if (serviceRoleKey.isEmpty) 'SUPABASE_SERVICE_ROLE_KEY',
  ];
  if (missing.isNotEmpty) {
    stderr.writeln('.env is missing ${missing.join(' and ')}. See .env.example.');
    exit(1);
  }

  final client = SupabaseClient(supabaseUrl, serviceRoleKey);

  stdout.writeln('Fetching peaks from Overpass …');
  final peaks = await _fetchPeaks();
  stdout.writeln('Found ${peaks.length} peaks. Upserting …');
  await _upsertInBatches(client, 'upsert_peaks', peaks);

  stdout.writeln('Fetching hiking routes from Overpass …');
  final routes = await _fetchHikingRoutes();
  stdout.writeln('Found ${routes.length} routes. Upserting …');
  await _upsertInBatches(client, 'upsert_hiking_routes', routes);

  stdout.writeln('Linking peaks to nearby routes …');
  await client.rpc('link_peaks_routes');

  stdout.writeln('Classifying peaks by mountain area …');
  await client.rpc('classify_peak_mountain_areas');

  stdout.writeln('Done.');
  exit(0);
}

// ---------------------------------------------------------------------------
// Overpass queries
// ---------------------------------------------------------------------------

Future<List<Map<String, dynamic>>> _fetchPeaks() async {
  const query = '''
    [out:json][timeout:180];
    area["ISO3166-1"="SI"][admin_level=2]->.si;
    (
      node["natural"="peak"]["name"](area.si);
      node["natural"="hill"]["name"](area.si);
    );
    out body;
  ''';

  final json = await _postOverpass(query);
  final elements = json['elements'] as List;

  return elements.map((e) {
    final el = e as Map<String, dynamic>;
    final tags = (el['tags'] as Map<String, dynamic>?) ?? {};
    // The query filters on ["name"], so every element that comes back has one.
    final name = tags['name'] as String;
    return {
      'id': el['id'],
      'name': name,
      'name_alt': tags['name:sl'] ?? tags['alt_name'],
      'elevation_m': _parseElevation(tags['ele'], name),
      'lat': el['lat'],
      'lon': el['lon'],
      'wikipedia': tags['wikipedia'],
      'description': tags['description'],
    };
  }).toList();
}

Future<List<Map<String, dynamic>>> _fetchHikingRoutes() async {
  const query = '''
    [out:json][timeout:180];
    area["ISO3166-1"="SI"][admin_level=2]->.si;
    relation["route"="hiking"](area.si);
    out geom;
  ''';

  final json = await _postOverpass(query);
  final elements = json['elements'] as List;

  final routes = <Map<String, dynamic>>[];
  for (final e in elements) {
    final el = e as Map<String, dynamic>;
    final tags = (el['tags'] as Map<String, dynamic>?) ?? {};
    final members = (el['members'] as List?) ?? [];

    final lines = <List<List<double>>>[];
    for (final m in members) {
      final member = m as Map<String, dynamic>;
      if (member['type'] != 'way') continue;
      final geometry = member['geometry'] as List?;
      if (geometry == null || geometry.isEmpty) continue;

      final line = geometry
          .map((pt) => [
                (pt as Map<String, dynamic>)['lon'] as num,
                pt['lat'] as num,
              ].map((n) => n.toDouble()).toList())
          .toList();
      lines.add(line);
    }

    if (lines.isEmpty) continue;

    routes.add({
      'id': el['id'],
      'name': tags['name'],
      'ref': tags['ref'],
      'from_name': tags['from'],
      'to_name': tags['to'],
      'difficulty': tags['sac_scale'],
      'distance_m': _lineDistanceMeters(lines).round(),
      'geojson': jsonEncode({
        'type': 'MultiLineString',
        'coordinates': lines,
      }),
    });
  }
  return routes;
}

Future<Map<String, dynamic>> _postOverpass(String query) async {
  final errors = <String>[];

  for (final mirror in _overpassMirrors) {
    for (var attempt = 0; attempt <= _retryDelays.length; attempt++) {
      try {
        final response = await http
            .post(
              Uri.parse(mirror),
              headers: {'User-Agent': 'uhribe-import-osm/1.0'},
              body: {'data': query},
            )
            // The [timeout:180] in the query binds Overpass, not us: without a
            // client-side cap a mirror that accepts the connection and then
            // goes quiet hangs the import forever instead of failing over.
            .timeout(_requestTimeout);
        if (response.statusCode == 200) {
          return jsonDecode(response.body) as Map<String, dynamic>;
        }
        errors.add('$mirror: HTTP ${response.statusCode}');
        // Only the busy codes are worth waiting out on this mirror. Anything
        // else goes straight to the next one rather than aborting the run —
        // a single mirror answering 502 is not a reason to give up on three.
        if (!_retryableStatusCodes.contains(response.statusCode)) break;
      } on SocketException catch (e) {
        errors.add('$mirror: $e');
      } on TimeoutException catch (e) {
        errors.add('$mirror: $e');
      } on http.ClientException catch (e) {
        errors.add('$mirror: $e');
      }

      if (attempt < _retryDelays.length) {
        final delay = _retryDelays[attempt];
        stderr.writeln(
            '  Overpass busy at $mirror, retrying in ${delay.inSeconds}s '
            '(attempt ${attempt + 1}/${_retryDelays.length + 1}) …');
        await Future<void>.delayed(delay);
      }
    }
    stderr.writeln('  Giving up on $mirror, trying next mirror …');
  }

  throw Exception('Overpass request failed on all mirrors:\n${errors.join('\n')}');
}

// ---------------------------------------------------------------------------
// Supabase upload
// ---------------------------------------------------------------------------

Future<void> _upsertInBatches(
  SupabaseClient client,
  String rpcName,
  List<Map<String, dynamic>> rows,
) async {
  for (var i = 0; i < rows.length; i += _batchSize) {
    final batch = rows.sublist(i, math.min(i + _batchSize, rows.length));
    await client.rpc(rpcName, params: {'p_rows': batch});
    stdout.writeln('  ${math.min(i + _batchSize, rows.length)}/${rows.length}');
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Parses an OSM `ele` tag into whole metres.
///
/// `ele` is free text, and the awkward values are the ones that matter: as
/// well as a plain `1234` there is `1234 m`, `4000 ft`, and — because much of
/// Europe punctuates numbers that way — `1.234` and `1,234` both meaning one
/// thousand two hundred thirty-four.
///
/// The earlier version stripped every non-digit and parsed the remainder,
/// which silently filed `1.234` as **1 m** and `4000 ft` as **4000 m**. A
/// wrong elevation is worse than a missing one here, because the peak list
/// sorts on it, so anything genuinely ambiguous is refused and reported
/// rather than guessed at.
int? _parseElevation(dynamic raw, String peakName) {
  if (raw == null) return null;
  final text = raw.toString().trim();
  if (text.isEmpty) return null;

  final isFeet = RegExp(r"(ft|feet|')\.?$", caseSensitive: false).hasMatch(text);
  var number = text.replaceAll(RegExp(r'[^0-9.,\-]'), '');

  // A sign anywhere but the front means a range ("1500-1600"), not a value.
  if (number.contains(RegExp(r'(?<=.)-'))) {
    stderr.writeln('  ! $peakName: ignoring ambiguous ele "$text"');
    return null;
  }

  final lastDot = number.lastIndexOf('.');
  final lastComma = number.lastIndexOf(',');
  if (lastDot >= 0 && lastComma >= 0) {
    // Both present, so whichever comes last is the decimal point and the
    // other groups thousands: "1,234.5" and "1.234,5" are the same number.
    number = lastDot > lastComma
        ? number.replaceAll(',', '')
        : number.replaceAll('.', '').replaceFirst(',', '.');
  } else if (lastDot >= 0 || lastComma >= 0) {
    number = _resolveSeparator(number, lastDot >= 0 ? '.' : ',');
  }

  final value = double.tryParse(number);
  if (value == null) {
    stderr.writeln('  ! $peakName: ignoring unparseable ele "$text"');
    return null;
  }
  return (isFeet ? value * 0.3048 : value).round();
}

/// Decides whether a lone `.` or `,` is a decimal point or a thousands mark.
///
/// Exactly three trailing digits means thousands — `1.234` is 1234 m, not a
/// summit 1.2 m above sea level quoted to the millimetre. Any other grouping
/// is a decimal point.
String _resolveSeparator(String number, String separator) {
  final parts = number.split(separator);
  if (parts.length == 2 && parts[1].length == 3) return parts.join();
  return number.replaceFirst(separator, '.');
}

/// Sum of great-circle distances along every line, in meters.
double _lineDistanceMeters(List<List<List<double>>> lines) {
  const earthRadiusM = 6371000.0;
  var total = 0.0;

  for (final line in lines) {
    for (var i = 0; i < line.length - 1; i++) {
      final lon1 = line[i][0], lat1 = line[i][1];
      final lon2 = line[i + 1][0], lat2 = line[i + 1][1];

      final dLat = _degToRad(lat2 - lat1);
      final dLon = _degToRad(lon2 - lon1);
      final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
          math.cos(_degToRad(lat1)) *
              math.cos(_degToRad(lat2)) *
              math.sin(dLon / 2) *
              math.sin(dLon / 2);
      final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
      total += earthRadiusM * c;
    }
  }
  return total;
}

double _degToRad(double deg) => deg * (math.pi / 180);

/// Minimal .env parser: KEY=VALUE per line, '#' comments.
///
/// Returns null when the file isn't there at all, which the caller reports
/// differently from a file that is present but incomplete — the usual cause
/// of the first is running this from the repo root instead of `tool/`, and
/// saying "copy .env.example" to someone who already has a .env is no help.
Map<String, String>? _loadEnv(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;

  final env = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final idx = trimmed.indexOf('=');
    if (idx == -1) continue;
    final key = trimmed.substring(0, idx).trim();
    var value = trimmed.substring(idx + 1).trim();
    // Quotes are optional here but habitual in .env files, and an unstripped
    // pair reaches SupabaseClient inside the URL, where it surfaces as an
    // opaque parse failure rather than anything pointing back at this file.
    if (value.length >= 2 &&
        (value.startsWith('"') && value.endsWith('"') ||
            value.startsWith("'") && value.endsWith("'"))) {
      value = value.substring(1, value.length - 1);
    }
    env[key] = value;
  }
  return env;
}
