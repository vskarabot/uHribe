import 'dart:io';
import 'dart:math' as math;

import 'package:supabase/supabase.dart';

const _upsertBatchSize = 500;
const _linkBatchSize = 100;

/// Builds a service-role client from tool/.env, or exits with a message
/// saying what is missing.
SupabaseClient connectFromEnv() {
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

  return SupabaseClient(supabaseUrl, serviceRoleKey);
}

Future<void> upsertInBatches(
  SupabaseClient client,
  String rpcName,
  List<Map<String, dynamic>> rows,
) async {
  for (var i = 0; i < rows.length; i += _upsertBatchSize) {
    final batch = rows.sublist(i, math.min(i + _upsertBatchSize, rows.length));
    await client.rpc(rpcName, params: {'p_rows': batch});
    stdout.writeln('  ${math.min(i + _upsertBatchSize, rows.length)}/${rows.length}');
  }
}

Future<void> linkPeaksToRoutes(SupabaseClient client, List<int> peakIds) async {
  for (var i = 0; i < peakIds.length; i += _linkBatchSize) {
    final batch = peakIds.sublist(i, math.min(i + _linkBatchSize, peakIds.length));
    await client.rpc('link_peaks_routes', params: {'p_peak_ids': batch});
    stdout.writeln('  ${math.min(i + _linkBatchSize, peakIds.length)}/${peakIds.length}');
  }
}

Future<List<int>> fetchAllPeakIds(SupabaseClient client) async {
  const pageSize = 1000;
  final ids = <int>[];
  for (var from = 0;; from += pageSize) {
    final rows = await client.from('peaks').select('id').order('id').range(from, from + pageSize - 1);
    ids.addAll(rows.map((r) => r['id'] as int));
    if (rows.length < pageSize) return ids;
  }
}

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
