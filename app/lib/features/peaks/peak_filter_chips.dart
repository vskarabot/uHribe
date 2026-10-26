import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../providers.dart';
import 'elevation_filter_sheet.dart';
import 'mountain_area_filter_sheet.dart';

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
