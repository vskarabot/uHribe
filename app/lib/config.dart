import 'package:flutter_dotenv/flutter_dotenv.dart';

/// App configuration, loaded from the bundled `.env` file at startup
/// (see [main.dart] — `dotenv.load()` is called before this is used).
///
/// Copy `.env.example` to `.env` and fill in your own values.
class Config {
  Config._();

  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';

  // The public "anon"/"publishable" key from Settings -> API. Safe to embed
  // in a client app; it only grants what your RLS policies allow.
  static String get supabasePublishableKey =>
      dotenv.env['SUPABASE_PUBLISHABLE_KEY'] ?? '';

  static String get mapboxAccessToken => dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '';

  /// The keys `.env` is missing, in the order `.env.example` lists them.
  ///
  /// Reported rather than just counted because every one of these fails
  /// *silently*: an empty Mapbox token leaves the map blank with no error at
  /// all, and an empty Supabase URL throws from inside the SDK before there is
  /// a widget tree to show it in. Naming the key is the whole point.
  static List<String> get missingKeys => [
        if (supabaseUrl.isEmpty) 'SUPABASE_URL',
        if (supabasePublishableKey.isEmpty) 'SUPABASE_PUBLISHABLE_KEY',
        if (mapboxAccessToken.isEmpty) 'MAPBOX_ACCESS_TOKEN',
      ];

  static bool get isConfigured => missingKeys.isEmpty;
}
