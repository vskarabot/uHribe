import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../providers.dart';

/// A small chip that appears while the app can't reach the server.
///
/// Nothing more: a queued check-in already shows as pending on the peak
/// itself, and it syncs on its own, so there is nothing here for the user to
/// do or count.
class OfflineChip extends ConsumerWidget {
  const OfflineChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(onlineStatusProvider)) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        // The error role, not tertiary: the green seed turns tertiary blue,
        // which reads as an informational badge rather than "something is
        // wrong right now".
        color: colorScheme.errorContainer,
        shape: const StadiumBorder(),
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 15, color: colorScheme.onErrorContainer),
              const SizedBox(width: 6),
              Text(
                Strings.offline,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onErrorContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
