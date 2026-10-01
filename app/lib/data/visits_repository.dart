import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/stats.dart';
import '../models/visit.dart';

class VisitsRepository {
  final SupabaseClient _client;

  VisitsRepository(this._client);

  /// Peak ids the current user has visited at least once.
  Future<Set<int>> fetchVisitedPeakIds() async {
    final rows = await _client.from('visits').select('peak_id');
    return (rows as List).map((r) => (r as Map<String, dynamic>)['peak_id'] as int).toSet();
  }

  Future<List<Visit>> fetchMyVisits() async {
    final rows = await _client
        .from('visits')
        .select('id, user_id, peak_id, route_id, visited_on, notes, created_at, '
            'distance_m, peaks(name, elevation_m)')
        .order('visited_on', ascending: false);
    return (rows as List).map((r) => Visit.fromJson(r as Map<String, dynamic>)).toList();
  }

  // Visits are created only by CheckInService, through the check_in_peak
  // RPC — inserting into this table directly is revoked.

  Future<void> deleteVisit(String id) async {
    await _client.from('visits').delete().eq('id', id);
  }

  Future<Stats> fetchMyStats() async {
    final rows = await _client.rpc('my_stats');
    final list = rows as List;
    if (list.isEmpty) return Stats.empty;
    return Stats.fromJson(list.first as Map<String, dynamic>);
  }
}
