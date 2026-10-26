import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/elevation_bracket.dart';
import '../../providers.dart';
import 'filter_sheet.dart';

Future<void> showElevationFilterSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (context) => const _ElevationFilterSheet(),
  );
}

class _ElevationFilterSheet extends ConsumerWidget {
  const _ElevationFilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedElevationBracketProvider);

    void choose(ElevationBracket? bracket) {
      ref.read(selectedElevationBracketProvider.notifier).set(bracket);
      Navigator.of(context).pop();
    }

    return FilterSheet(
      title: Strings.filterByElevation,
      options: [
        FilterOption(
          label: Strings.allElevations,
          selected: selected == null,
          onTap: () => choose(null),
        ),
        for (final bracket in ElevationBracket.all)
          FilterOption(
            label: bracket.label,
            selected: selected == bracket,
            onTap: () => choose(bracket),
          ),
      ],
    );
  }
}
