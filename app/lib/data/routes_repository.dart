import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/hiking_route.dart';

class RoutesRepository {
  final SupabaseClient _client;

  RoutesRepository(this._client);

  Future<List<HikingRoute>> fetchForPeak(int peakId) async {
    final rows = await _client.rpc('routes_for_peak', params: {'p_peak_id': peakId});
    return (rows as List).map((r) => HikingRoute.fromJson(r as Map<String, dynamic>)).toList();
  }
}
