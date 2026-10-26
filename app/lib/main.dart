import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'providers.dart';
import 'router.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load();
  } catch (_) {
  }

  final missingKeys = Config.missingKeys;
  if (missingKeys.isNotEmpty) {
    runApp(_MisconfiguredApp(missingKeys: missingKeys));
    return;
  }

  MapboxOptions.setAccessToken(Config.mapboxAccessToken);

  await Supabase.initialize(
    url: Config.supabaseUrl,
    publishableKey: Config.supabasePublishableKey,
  );

  runApp(const ProviderScope(child: UhribeApp()));
}

class _MisconfiguredApp extends StatelessWidget {
  const _MisconfiguredApp({required this.missingKeys});

  final List<String> missingKeys;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Manjka konfiguracija',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Text(
                  'V app/.env manjka:\n${missingKeys.map((k) => '  • $k').join('\n')}',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Kopirajte app/.env.example v app/.env in izpolnite vrednosti. '
                  '.env se pakira kot sredstvo (asset), zato je po spremembi '
                  'potreben ponoven zagon (hot restart ne zadošča).',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class UhribeApp extends ConsumerWidget {
  const UhribeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'uHribe',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: child,
      ),
    );
  }
}
