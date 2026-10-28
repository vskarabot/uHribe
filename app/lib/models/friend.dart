enum FriendshipStatus {
  none,
  friends,
  incoming,
  outgoing;

  static FriendshipStatus parse(String? value) {
    return FriendshipStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => FriendshipStatus.none,
    );
  }
}

class Friend {
  final String userId;
  final String? displayName;
  final String? avatarUrl;
  final String? homeRegion;
  final FriendshipStatus status;

  const Friend({
    required this.userId,
    this.displayName,
    this.avatarUrl,
    this.homeRegion,
    required this.status,
  });

  factory Friend.fromJson(Map<String, dynamic> json) {
    return Friend(
      userId: json['user_id'] as String,
      displayName: json['display_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      homeRegion: json['home_region'] as String?,
      status: FriendshipStatus.parse(json['status'] as String?),
    );
  }

  Friend copyWith({FriendshipStatus? status}) {
    return Friend(
      userId: userId,
      displayName: displayName,
      avatarUrl: avatarUrl,
      homeRegion: homeRegion,
      status: status ?? this.status,
    );
  }
}

class FeedItem {
  final String visitId;
  final String userId;
  final String? displayName;
  final String? avatarUrl;
  final int peakId;
  final String peakName;
  final int? elevationM;
  final DateTime visitedOn;

  const FeedItem({
    required this.visitId,
    required this.userId,
    this.displayName,
    this.avatarUrl,
    required this.peakId,
    required this.peakName,
    this.elevationM,
    required this.visitedOn,
  });

  factory FeedItem.fromJson(Map<String, dynamic> json) {
    return FeedItem(
      visitId: json['visit_id'] as String,
      userId: json['user_id'] as String,
      displayName: json['display_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      peakId: json['peak_id'] as int,
      peakName: json['peak_name'] as String,
      elevationM: json['elevation_m'] as int?,
      visitedOn: DateTime.parse(json['visited_on'] as String),
    );
  }
}
