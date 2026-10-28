import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/friend.dart';

class SocialRepository {
  final SupabaseClient _client;

  SocialRepository(this._client);

  Future<List<Friend>> fetchFriends() async {
    final rows = await _client.rpc('my_friends');
    return (rows as List).map((r) => Friend.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<List<Friend>> search(String query) async {
    final rows = await _client.rpc('search_profiles', params: {'p_query': query});
    return (rows as List).map((r) => Friend.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<FriendshipStatus> sendRequest(String userId) async {
    final status = await _client.rpc('send_friend_request', params: {'p_user_id': userId});
    return FriendshipStatus.parse(status as String?);
  }

  Future<void> acceptRequest(String userId) async {
    await _client.rpc('accept_friend_request', params: {'p_user_id': userId});
  }

  Future<void> removeFriendship(String userId) async {
    await _client.rpc('remove_friendship', params: {'p_user_id': userId});
  }

  Future<List<FeedItem>> fetchFeed() async {
    final rows = await _client.rpc('friends_feed');
    return (rows as List).map((r) => FeedItem.fromJson(r as Map<String, dynamic>)).toList();
  }
}
