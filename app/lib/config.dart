import 'package:flutter_dotenv/flutter_dotenv.dart';

class Config {
  Config._();

  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';

  static String get supabasePublishableKey =>
      dotenv.env['SUPABASE_PUBLISHABLE_KEY'] ?? '';

  static String get mapboxAccessToken => dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '';

  static List<String> get missingKeys => [
        if (supabaseUrl.isEmpty) 'SUPABASE_URL',
        if (supabasePublishableKey.isEmpty) 'SUPABASE_PUBLISHABLE_KEY',
        if (mapboxAccessToken.isEmpty) 'MAPBOX_ACCESS_TOKEN',
      ];

  static bool get isConfigured => missingKeys.isEmpty;
}
