import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../providers.dart';
import '../map/map_screen.dart';
import '../peaks/peak_list_screen.dart';
import '../profile/profile_screen.dart';
import '../settings/settings_screen.dart';
import 'bottom_fade_scrim.dart';
import 'offline_chip.dart';
import 'pill_nav_bar.dart';

/// Bottom-navigation shell hosting the four main tabs. Each tab keeps its
/// state alive via [IndexedStack] while switching.
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
    ProfileScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    // A peak was selected elsewhere (e.g. the peak list) — switch to the map
    // tab so it can center on it; the map screen itself does the flying.
    ref.listen(peakFocusProvider, (_, next) {
      if (next != null) setState(() => _index = _mapTabIndex);
    });

    // With the keyboard up the screen is already half gone, and whatever the
    // typing produced — the map's search results — is what's left. Frosting
    // the bottom of that is the one moment the scrim costs more than it buys.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      extendBody: true,
      // Each tab decides for itself what the keyboard does to it — the map
      // wants to be left at full size, a form wants to be pushed up — and it
      // can't if the shell has already shrunk the body they all sit in.
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          IndexedStack(index: _index, children: _tabs),
          // Drawn over the tab but under the nav bar (Scaffold paints
          // bottomNavigationBar last), so content dissolves into the bottom of
          // the screen on its way under the floating bar.
          if (!keyboardOpen)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: BottomFadeScrim(height: PillNavBar.centerOffset(context)),
            ),
          // Floats over the content rather than taking a row, so it doesn't
          // shove the map down every time signal drops. Nothing on it is
          // tappable, so it lets touches through to whatever is underneath.
          //
          // The map tab is the exception: its own search field and filters
          // already own the top of the screen, so a chip pinned there lands
          // on top of them. That tab draws the chip itself, under its
          // filters — see MapScreen.
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
