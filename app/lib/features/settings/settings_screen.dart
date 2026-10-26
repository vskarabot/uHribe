import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../l10n/strings.dart';
import '../../providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text(Strings.navSettings)),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            sliver: SliverList.list(
              children: [
                _SettingsGroup(
                  children: [
                    _SettingsRow(
                      icon: Icons.tune,
                      title: Strings.settingsGeneral,
                      subtitle: Strings.settingsGeneralSubtitle,
                      onTap: () => _open(context, const _GeneralSettingsPage()),
                    ),
                    _SettingsRow(
                      icon: Icons.info_outline,
                      title: Strings.settingsAbout,
                      onTap: () => _open(context, const _AboutPage()),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _SettingsGroup(
                  children: [
                    _SettingsRow(
                      icon: Icons.logout,
                      title: Strings.logout,
                      showChevron: false,
                      onTap: () => ref.read(authRepositoryProvider).signOut(),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Align(alignment: Alignment.bottomCenter, child: _RightsFooter()),
          ),
        ],
      ),
    );
  }
}

void _open(BuildContext context, Widget page) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
}

class _SettingsGroup extends StatelessWidget {
  final List<Widget> children;

  const _SettingsGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 56),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool showChevron;

  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: showChevron ? const Icon(Icons.chevron_right) : null,
      onTap: onTap,
    );
  }
}

class _RightsFooter extends StatelessWidget {
  const _RightsFooter();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 32, 20, MediaQuery.paddingOf(context).bottom + 16),
      child: Text(
        Strings.copyright,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _GeneralSettingsPage extends ConsumerWidget {
  const _GeneralSettingsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(myProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(Strings.settingsGeneral)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _SettingsGroup(
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
                onChanged: profileAsync.value == null
                    ? null
                    : (on) => _setLocationEnabled(context, ref, on),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AboutPage extends StatelessWidget {
  const _AboutPage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text(Strings.settingsAbout)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            Strings.appName,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(Strings.appTagline, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 24),
          Text(
            Strings.dataSources,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const _SettingsGroup(
            children: [
              ListTile(
                leading: Icon(Icons.landscape_outlined),
                title: Text(Strings.peakDataSource),
                subtitle: Text(Strings.osmAttribution),
              ),
              ListTile(
                leading: Icon(Icons.map_outlined),
                title: Text(Strings.mapDataSource),
                subtitle: Text(Strings.mapboxAttribution),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

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
