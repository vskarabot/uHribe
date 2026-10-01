import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../providers.dart';
import 'elevation_filter_sheet.dart';
import 'mountain_area_filter_sheet.dart';

/// The area and elevation filters, as a pair of chips.
///
/// Shared by the peak list and the map rather than built once per screen:
/// both read the same two providers, so a filter offered on one and not the
/// other — or cleared differently there — is the list and the map disagreeing
/// about what the user asked for.
class PeakFilterChips extends ConsumerWidget {
  const PeakFilterChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedArea = ref.watch(selectedMountainAreaProvider);
    final selectedElevation = ref.watch(selectedElevationBracketProvider);

    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        alignment: WrapAlignment.start,
        spacing: 8,
        runSpacing: 8,
        children: [
          PeakFilterChip(
            icon: Icons.filter_alt_outlined,
            label: selectedArea ?? Strings.allAreas,
            active: selectedArea != null,
            onTap: () => showMountainAreaFilterSheet(context),
            onClear: () => ref.read(selectedMountainAreaProvider.notifier).set(null),
          ),
          PeakFilterChip(
            icon: Icons.height,
            label: selectedElevation?.label ?? Strings.allElevations,
            active: selectedElevation != null,
            onTap: () => showElevationFilterSheet(context),
            onClear: () =>
                ref.read(selectedElevationBracketProvider.notifier).set(null),
          ),
        ],
      ),
    );
  }
}

/// One filter, in either of two clearly different states.
///
/// Both used to be the same neutral chip whose only tell was the label text,
/// so an applied filter looked exactly like an unapplied one and a shortened
/// list had no visible cause. Applied now means filled, bolder, and carrying
/// its own × — the way out has to be as visible as the way in.
class PeakFilterChip extends StatelessWidget {
  const PeakFilterChip({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    required this.onClear,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClear;

  /// Area names run long enough ("Goriško, Notranjsko in Snežniško hribovje")
  /// to push a chip past the screen edge, which on the map means a control
  /// half off-screen over the terrain. Truncate instead; the sheet and the
  /// tooltip both still show it in full.
  static const _maxLabelWidth = 200.0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final labelWidget = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _maxLabelWidth),
      child: Text(label, overflow: TextOverflow.ellipsis, softWrap: false),
    );

    if (!active) {
      return ActionChip(
        avatar: Icon(icon, size: 16),
        label: labelWidget,
        onPressed: onTap,
        tooltip: label,
      );
    }

    return InputChip(
      avatar: Icon(icon, size: 16, color: colorScheme.onSecondaryContainer),
      label: labelWidget,
      selected: true,
      // The avatar already says which filter this is; a checkmark on top of
      // it just crowds the chip.
      showCheckmark: false,
      labelStyle: TextStyle(
        fontWeight: FontWeight.w600,
        color: colorScheme.onSecondaryContainer,
      ),
      side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.35)),
      onPressed: onTap,
      onDeleted: onClear,
      deleteIcon: const Icon(Icons.close, size: 16),
      deleteIconColor: colorScheme.onSecondaryContainer,
      tooltip: label,
    );
  }
}
