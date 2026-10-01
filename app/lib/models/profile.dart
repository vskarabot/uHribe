class Profile {
  final String id;
  final String? email;
  final String? displayName;
  final String? avatarUrl;
  final String? homeRegion;

  /// Whether the user opted into showing their location on the map. Stored
  /// server-side so a fresh install/login can show the puck without asking
  /// again; the OS permission still decides whether it actually can.
  final bool locationEnabled;

  const Profile({
    required this.id,
    this.email,
    this.displayName,
    this.avatarUrl,
    this.homeRegion,
    this.locationEnabled = false,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      email: json['email'] as String?,
      displayName: json['display_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      homeRegion: json['home_region'] as String?,
      locationEnabled: json['location_enabled'] as bool? ?? false,
    );
  }

  Profile copyWith({
    String? displayName,
    String? avatarUrl,
    String? homeRegion,
    bool? locationEnabled,
  }) {
    return Profile(
      id: id,
      email: email,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      homeRegion: homeRegion ?? this.homeRegion,
      locationEnabled: locationEnabled ?? this.locationEnabled,
    );
  }
}
