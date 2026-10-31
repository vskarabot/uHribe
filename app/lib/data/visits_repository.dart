import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/stats.dart';
import '../models/visit.dart';

class VisitsRepository {
  final SupabaseClient _client;

  VisitsRepository(this._client);

  Future<Set<int>> fetchVisitedPeakIds() async {
    final rows = await _client.from('visits').select('peak_id');
    return (rows as List).map((r) => (r as Map<String, dynamic>)['peak_id'] as int).toSet();
  }

  Future<List<Visit>> fetchMyVisits() async {
    final rows = await _client
        .from('visits')
        .select('id, user_id, peak_id, route_id, visited_on, notes, created_at, '
            'device_time, distance_m, peaks(name, elevation_m)')
        .order('visited_on', ascending: false);
    final visits =
        (rows as List).map((r) => Visit.fromJson(r as Map<String, dynamic>)).toList();
    visits.sort((a, b) {
      final byDay = b.visitedOn.compareTo(a.visitedOn);
      return byDay != 0 ? byDay : b.visitedAt.compareTo(a.visitedAt);
    });
    return visits;
  }

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
