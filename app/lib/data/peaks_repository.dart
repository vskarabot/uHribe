import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/peak.dart';

class PeaksRepository {
  final SupabaseClient _client;

  PeaksRepository(this._client);

  static const _columns =
      'id, name, name_alt, elevation_m, lat, lon, wikipedia, description, mountain_area, '
      'checkin_radius_m';

  PostgrestTransformBuilder<PostgrestList> _peaksQuery() => _client
      .from('peaks')
      .select(_columns)
      .order('elevation_m', ascending: false)
      .order('id');

  Future<List<Peak>> fetchAll() async {
    const pageSize = 1000;

    final first = await _peaksQuery().range(0, pageSize - 1).count(CountOption.exact);
    final peaks = first.data.map((r) => Peak.fromJson(r)).toList();

    final pageCount = (first.count / pageSize).ceil();
    if (pageCount > 1) {
      final rest = await Future.wait([
        for (var page = 1; page < pageCount; page++)
          _peaksQuery().range(page * pageSize, page * pageSize + pageSize - 1),
      ]);
      for (final rows in rest) {
        peaks.addAll(rows.map((r) => Peak.fromJson(r)));
      }
    }

    return peaks;
  }

  Future<Peak?> fetchById(int id) async {
    final row = await _client
        .from('peaks')
        .select(_columns)
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    return Peak.fromJson(row);
  }
}
