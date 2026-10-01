import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';

class ProfileRepository {
  final SupabaseClient _client;

  ProfileRepository(this._client);

  Future<Profile> fetchMine() async {
    final userId = _client.auth.currentUser!.id;
    final row = await _client.from('profiles').select().eq('id', userId).single();
    return Profile.fromJson(row);
  }

  /// Uploads a picked photo as the user's avatar and returns its public URL.
  Future<String> uploadAvatar(Uint8List bytes, String fileExt) async {
    final userId = _client.auth.currentUser!.id;
    final path = '$userId/avatar.$fileExt';
    await _client.storage.from('avatars').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true),
        );
    final url = _client.storage.from('avatars').getPublicUrl(path);
    // Bust caches on re-upload since the path never changes.
    return '$url?t=${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> update({
    String? displayName,
    String? avatarUrl,
    String? homeRegion,
    bool? locationEnabled,
  }) async {
    final userId = _client.auth.currentUser!.id;
    await _client.from('profiles').update({
      if (displayName != null) 'display_name': displayName,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (homeRegion != null) 'home_region': homeRegion,
      if (locationEnabled != null) 'location_enabled': locationEnabled,
    }).eq('id', userId);
  }
}
