import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../providers.dart';
import '../map/map_screen.dart';
import '../peaks/peak_list_screen.dart';
import '../profile/profile_screen.dart';
import '../settings/settings_screen.dart';
import '../social/feed_screen.dart';
import 'bottom_fade_scrim.dart';
import 'offline_chip.dart';
import 'pill_nav_bar.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  static const _mapTabIndex = 1;

  int _index = 0;

  static const _tabs = [
    PeakListScreen(),
    MapScreen(),
    FeedScreen(),
    ProfileScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    ref.listen(peakFocusProvider, (_, next) {
      if (next != null) setState(() => _index = _mapTabIndex);
    });

    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      extendBody: true,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          IndexedStack(index: _index, children: _tabs),
          if (!keyboardOpen)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: BottomFadeScrim(height: PillNavBar.centerOffset(context)),
            ),
          if (_index != _mapTabIndex)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: SafeArea(
                  bottom: false,
                  child: Align(alignment: Alignment.topCenter, child: OfflineChip()),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: PillNavBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          PillNavDestination(
            icon: Icons.landscape_outlined,
            selectedIcon: Icons.landscape,
            label: Strings.navPeaks,
          ),
          PillNavDestination(
            icon: Icons.map_outlined,
            selectedIcon: Icons.map,
            label: Strings.navMap,
          ),
          PillNavDestination(
            icon: Icons.dynamic_feed_outlined,
            selectedIcon: Icons.dynamic_feed,
            label: Strings.navFeed,
          ),
          PillNavDestination(
            icon: Icons.person_outline,
            selectedIcon: Icons.person,
            label: Strings.navProfile,
          ),
          PillNavDestination(
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings,
            label: Strings.navSettings,
          ),
        ],
      ),
    );
  }
}
