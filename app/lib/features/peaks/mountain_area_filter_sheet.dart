import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../providers.dart';
import 'filter_sheet.dart';

/// Modal bottom sheet for picking the mountain area to filter peaks by.
/// Shared between the peaks list and map screens via [selectedMountainAreaProvider].
Future<void> showMountainAreaFilterSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (context) => const _MountainAreaFilterSheet(),
  );
}

class _MountainAreaFilterSheet extends ConsumerWidget {
  const _MountainAreaFilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedMountainAreaProvider);

    void choose(String? area) {
      ref.read(selectedMountainAreaProvider.notifier).set(area);
      Navigator.of(context).pop();
    }

    return FilterSheet(
      title: Strings.filterByArea,
      options: [
        FilterOption(
          label: Strings.allAreas,
          selected: selected == null,
          onTap: () => choose(null),
        ),
        for (final area in Strings.mountainAreas)
          FilterOption(
            label: area,
            selected: selected == area,
            onTap: () => choose(area),
          ),
      ],
    );
  }
}
