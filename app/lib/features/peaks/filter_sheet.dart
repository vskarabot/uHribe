import 'package:flutter/material.dart';

/// One row in a [FilterSheet].
class FilterOption {
  const FilterOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
}

/// The shared body of the filter sheets, built to read as a continuation of
/// the peaks list rather than as its own little world: the same small bold
/// section heading, the same inset hairline between rows, and the same row
/// weight — so opening a filter doesn't feel like leaving the page.
class FilterSheet extends StatelessWidget {
  const FilterSheet({super.key, required this.title, required this.options});

  final String title;
  final List<FilterOption> options;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          Divider(height: 1, thickness: 0.5, color: colorScheme.outlineVariant),
          // Flexible, not Expanded: a short list should size to its rows
          // while a long one still stops at the sheet's height and scrolls.
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: options.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                thickness: 0.5,
                indent: 16,
                endIndent: 16,
                color: colorScheme.outlineVariant,
              ),
              itemBuilder: (context, index) {
                final option = options[index];
                return ListTile(
                  title: Text(
                    option.label,
                    style: TextStyle(
                      fontWeight: option.selected ? FontWeight.w700 : FontWeight.w500,
                      color: option.selected ? colorScheme.primary : null,
                    ),
                  ),
                  trailing: option.selected
                      ? Icon(Icons.check, size: 18, color: colorScheme.primary)
                      : null,
                  onTap: option.onTap,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
