// Imports Slovenian peaks and hiking routes from OpenStreetMap (via the
// Overpass API) into Supabase. Only peaks that match a summit on the
// reference list (lib/reference_peaks.dart) are kept.
//
// Usage:
//   cd tool
//   dart pub get
//   cp .env.example .env   # fill in SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY
//   dart run import_osm.dart                 # add --skip-routes to keep the routes already imported
//
// Safe to re-run: everything is upserted by OSM id, so running it again just
// refreshes the data.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:uhribe_import/import_common.dart';
import 'package:uhribe_import/reference_peaks.dart';

const _overpassMirrors = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.kumi.systems/api/interpreter',
  'https://overpass.openstreetmap.ru/api/interpreter',
  'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
];
const _retryDelays = [Duration(seconds: 5), Duration(seconds: 15), Duration(seconds: 45)];
const _retryableStatusCodes = {429, 503, 504};
/// Client-side cap on one Overpass request. Comfortably longer than the
/// server's own [timeout:180], so a mirror that is merely slow still gets to
/// answer, while one that has gone silent is given up on.
const _requestTimeout = Duration(seconds: 240);
/// An OSM peak matches a reference summit of the same name whose elevation
/// is within this many metres of its own.
const _elevationToleranceM = 30;

Future<void> main(List<String> args) async {
  final client = connectFromEnv();
  final skipRoutes = args.contains('--skip-routes');

  stdout.writeln('Fetching reference summit list …');
  final reference = await fetchReferencePeaks();
  stdout.writeln('  ${reference.length} entries.');

  stdout.writeln('Fetching peaks from Overpass …');
  final allPeaks = await _fetchPeaks();
  final peaks = _matchToReference(allPeaks, reference);
  stdout.writeln('Kept ${peaks.length} of ${allPeaks.length} peaks. Upserting …');
  await upsertInBatches(client, 'upsert_peaks', peaks);

  if (!skipRoutes) {
    stdout.writeln('Fetching hiking routes from Overpass …');
    final routes = await _fetchHikingRoutes();
    stdout.writeln('Found ${routes.length} routes. Upserting …');
    await upsertInBatches(client, 'upsert_hiking_routes', routes);
  }

  final peakIds = peaks.map((p) => p['id'] as int).toList();

  stdout.writeln('Removing peaks not on the reference list …');
  final removed = await client.rpc('prune_unlisted_peaks', params: {'p_keep_ids': peakIds});
  stdout.writeln('  Removed $removed peaks.');

  stdout.writeln('Linking peaks to nearby routes …');
  await linkPeaksToRoutes(client, await fetchAllPeakIds(client));

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
      'lat': (el['lat'] as num).toDouble(),
      'lon': (el['lon'] as num).toDouble(),
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
          final json = jsonDecode(response.body) as Map<String, dynamic>;
          // An overloaded server can answer 200 with a "remark" and no
          // elements; taken at face value that prunes every peak.
          if ((json['elements'] as List?)?.isNotEmpty ?? false) return json;
          errors.add('$mirror: empty result ${json['remark'] ?? ''}');
          break;
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
// Helpers
// ---------------------------------------------------------------------------

List<Map<String, dynamic>> _matchToReference(
  List<Map<String, dynamic>> peaks,
  List<ReferencePeak> reference,
) {
  final elevationsByName = <String, List<int?>>{};
  for (final ref in reference) {
    for (final name in ref.names.map(_normalizeName).toSet()) {
      elevationsByName.putIfAbsent(name, () => []).add(ref.elevation);
    }
  }

  return peaks.where((p) {
    final ele = p['elevation_m'] as int?;
    final names = [p['name'], p['name_alt']].whereType<String>().map(_normalizeName);
    return names.any((n) {
      final elevations = elevationsByName[n];
      if (elevations == null) return false;
      // Without an OSM elevation, only a name that occurs once is safe to trust.
      if (ele == null) return elevations.length == 1;
      return elevations.any((e) => e != null && (e - ele).abs() <= _elevationToleranceM);
    });
  }).toList();
}

String _normalizeName(String name) {
  const folds = {'č': 'c', 'ć': 'c', 'š': 's', 'ž': 'z', 'đ': 'd', 'ô': 'o', 'é': 'e', 'è': 'e', 'à': 'a', 'ü': 'u', 'ö': 'o', 'ä': 'a'};
  final lower = name.toLowerCase();
  final buffer = StringBuffer();
  for (final ch in lower.split('')) {
    buffer.write(folds[ch] ?? ch);
  }
  return buffer.toString().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

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
