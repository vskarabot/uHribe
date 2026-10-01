import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../l10n/strings.dart';
import '../../providers.dart';

/// App-wide preferences: appearance and location access.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(myProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(Strings.navSettings)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text(Strings.darkMode),
                  secondary: const Icon(Icons.dark_mode_outlined),
                  value: ref.watch(themeModeProvider) == ThemeMode.dark,
                  onChanged: (dark) => ref.read(themeModeProvider.notifier).setDark(dark),
                ),
                SwitchListTile(
                  title: const Text(Strings.locationSetting),
                  secondary: const Icon(Icons.my_location),
                  value: profileAsync.value?.locationEnabled ?? false,
                  // Disabled until the profile loads, so a tap can't write
                  // a preference we haven't read yet.
                  onChanged: profileAsync.value == null
                      ? null
                      : (on) => _setLocationEnabled(context, ref, on),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Turning the map's location display on asks for the OS permission up front,
/// so the stored preference never promises something the system will refuse;
/// turning it off just clears the preference.
Future<void> _setLocationEnabled(BuildContext context, WidgetRef ref, bool on) async {
  if (!on) {
    await rememberLocationEnabled(ref, false);
    return;
  }

  if (!await Geolocator.isLocationServiceEnabled()) {
    if (context.mounted) _showError(context, Strings.locationServicesDisabled);
    return;
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.deniedForever) {
    if (context.mounted) {
      _showError(context, Strings.locationPermissionDeniedForever, openSettings: true);
    }
    return;
  }
  if (permission == LocationPermission.denied) {
    if (context.mounted) _showError(context, Strings.locationPermissionDenied);
    return;
  }

  await rememberLocationEnabled(ref, true);
}

void _showError(BuildContext context, String message, {bool openSettings = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      // Floated clear of the shell's pill nav bar, which otherwise covers a
      // bottom-anchored snack bar.
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.paddingOf(context).bottom + 16),
      action: openSettings
          ? SnackBarAction(
              label: Strings.openSettings,
              onPressed: Geolocator.openAppSettings,
            )
          : null,
    ),
  );
}
