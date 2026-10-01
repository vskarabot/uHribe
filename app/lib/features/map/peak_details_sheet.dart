import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' show Geolocator;
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/strings.dart';
import '../../models/hiking_route.dart';
import '../../models/peak.dart';
import '../../providers.dart';
import '../../services/checkin_service.dart';
import '../../services/location_service.dart';

/// Shows [peakId]'s details in a draggable bottom sheet over whatever's
/// currently on screen (the map, centered and zoomed in on the peak).
Future<void> showPeakDetailsSheet(BuildContext context, int peakId) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // Corner and handle come from the app's bottomSheetTheme, so this sheet
    // can't drift away from the filter sheets.
    builder: (context) => PeakDetailsSheet(peakId: peakId),
  );
}

class PeakDetailsSheet extends ConsumerWidget {
  final int peakId;

  const PeakDetailsSheet({super.key, required this.peakId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peakAsync = ref.watch(peakByIdProvider(peakId));
    final routesAsync = ref.watch(routesForPeakProvider(peakId));
    final visitedIds = ref.watch(visitedPeakIdsProvider).value ?? const <int>{};
    // A check-in still sitting in the device queue counts as climbed here —
    // the user stood on the summit, the server just hasn't been told yet.
    final pendingIds = ref.watch(pendingPeakIdsProvider);
    final downloadedIds = ref.watch(offlinePeakIdsProvider).value ?? const <int>{};
    final online = ref.watch(onlineStatusProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      minChildSize: 0.25,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return peakAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const Center(child: Text(Strings.loadError)),
          data: (peak) {
            if (peak == null) {
              return const Center(child: Text(Strings.loadError));
            }
            final pending = pendingIds.contains(peak.id);
            final visited = visitedIds.contains(peak.id) || pending;
            final downloaded = downloadedIds.contains(peak.id);
            final colorScheme = Theme.of(context).colorScheme;

            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Matched to the home page's app-bar title. At the
                          // 26/w800 this was, the sheet read as a different
                          // app's screen than the list that opened it.
                          Text(
                            peak.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              height: 1.15,
                            ),
                          ),
                          // Height and range on one line under the name, the
                          // same shape as a peak row in the list. Standing in
                          // its own band below, the height had nothing to sit
                          // against once it stopped being a huge number.
                          if (peak.elevationM != null || peak.mountainArea != null) ...[
                            const SizedBox(height: 3),
                            Text.rich(
                              TextSpan(
                                children: [
                                  if (peak.elevationM != null)
                                    TextSpan(
                                      text: '${peak.elevationM} m',
                                      style: TextStyle(
                                        color: colorScheme.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  if (peak.elevationM != null && peak.mountainArea != null)
                                    const TextSpan(text: '  |  '),
                                  if (peak.mountainArea != null)
                                    TextSpan(text: peak.mountainArea!),
                                ],
                              ),
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _toggleDownload(context, ref, peak, downloaded),
                      icon: Icon(
                        downloaded ? Icons.offline_pin : Icons.download_for_offline_outlined,
                        color: downloaded ? colorScheme.primary : null,
                      ),
                      tooltip: downloaded
                          ? Strings.downloadedForOffline
                          : Strings.downloadForOffline,
                      style: IconButton.styleFrom(
                        backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      ),
                    ),
                    if (peak.wikipedia != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => _openWikipedia(peak.wikipedia!),
                        icon: const Icon(Icons.menu_book_outlined),
                        tooltip: Strings.wikipediaLink,
                        style: IconButton.styleFrom(
                          backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                    if (visited) ...[
                      const SizedBox(width: 8),
                      Chip(
                        avatar: Icon(
                          pending ? Icons.cloud_upload_outlined : Icons.check_circle,
                          size: 18,
                        ),
                        label: Text(
                          pending ? Strings.pendingBadge : Strings.alreadyVisited,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                _SheetDivider(),
                const SizedBox(height: 14),
                _InfoRow(
                  icon: Icons.place_outlined,
                  label: Strings.coordinates,
                  value: '${peak.lat.toStringAsFixed(5)}, ${peak.lon.toStringAsFixed(5)}',
                ),
                if (peak.description != null && peak.description!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(peak.description!),
                ],
                const SizedBox(height: 20),
                // The only way to record this peak: be standing on it.
                FilledButton.icon(
                  icon: const Icon(Icons.flag),
                  label: const Text(Strings.checkIn),
                  onPressed: () => _checkIn(context, ref, peak),
                ),
                const SizedBox(height: 22),
                _SheetDivider(),
                const SizedBox(height: 16),
                // Same 13/w700 as the "Vrhovi" heading over the peaks list.
                Text(
                  Strings.routesTitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                routesAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, _) => const Text(Strings.loadError),
                  data: (routes) {
                    if (routes.isEmpty) {
                      // Offline, an empty list means nothing was downloaded —
                      // saying "this peak has no known routes" would be a
                      // claim about the mountain we can't make from here.
                      return Text(online ? Strings.noRoutes : Strings.routesOffline);
                    }
                    return Column(
                      children: routes.map((r) => _RouteTile(route: r)).toList(growable: false),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _toggleDownload(
    BuildContext context,
    WidgetRef ref,
    Peak peak,
    bool downloaded,
  ) async {
    try {
      await setPeakDownloaded(ref, peak.id, !downloaded);
    } catch (_) {
      if (!context.mounted) return;
      _snack(context, Strings.downloadFailed);
    }
  }

  /// Takes a fix and records the ascent, online or not.
  ///
  /// Sampling takes several seconds — longer on a cold start with no network
  /// to hand the receiver its assistance data — so the wait is explicit
  /// rather than a frozen button.
  Future<void> _checkIn(BuildContext context, WidgetRef ref, Peak peak) async {
    final service = ref.read(checkInServiceProvider);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
            SizedBox(width: 20),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(Strings.checkInSearching),
                  SizedBox(height: 4),
                  Text(Strings.checkInSearchingHint, style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    CheckInOutcome? outcome;
    Object? error;
    try {
      outcome = await service.checkIn(peak: peak);
    } catch (e) {
      error = e;
    }

    if (!context.mounted) return;
    Navigator.of(context).pop(); // the progress dialog

    if (outcome != null) {
      // The queue changed either way: a synced check-in left it, a queued one
      // joined it.
      await ref.read(pendingCheckInsProvider.notifier).reload();
      if (outcome.status == CheckInStatus.recorded) {
        invalidateUserData(ref);
      }
      if (!context.mounted) return;
      _snack(context, switch (outcome.status) {
        CheckInStatus.recorded => Strings.checkInRecorded,
        CheckInStatus.queued => Strings.checkInQueued,
        // Refused by the server. It stays in the pending list on the profile
        // with the reason, rather than disappearing here.
        CheckInStatus.rejected => Strings.checkInFailed,
      });
      return;
    }

    switch (error) {
      case TooFarException e:
        await _showTooFarDialog(context, e);
      case MockedLocationException _:
        _snack(context, Strings.checkInMocked);
      case LocationException e:
        _snack(
          context,
          _locationMessage(e.failure),
          openSettings: e.failure == LocationFailure.permissionDeniedForever,
        );
      default:
        _snack(context, Strings.checkInFailed);
    }
  }

  Future<void> _showTooFarDialog(BuildContext context, TooFarException e) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(Strings.checkInTooFarTitle),
        content: Text(
          Strings.checkInTooFarBody(e.distanceM.round(), e.allowedM.round()),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(Strings.ok),
          ),
        ],
      ),
    );
  }

  String _locationMessage(LocationFailure failure) => switch (failure) {
        LocationFailure.servicesDisabled => Strings.locationServicesDisabled,
        LocationFailure.permissionDenied => Strings.locationPermissionDenied,
        LocationFailure.permissionDeniedForever => Strings.locationPermissionDeniedForever,
        LocationFailure.unavailable => Strings.locationUnavailable,
      };

  void _snack(BuildContext context, String message, {bool openSettings = false}) {
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

  Future<void> _openWikipedia(String wikipedia) async {
    final uri = wikipedia.startsWith('http')
        ? Uri.parse(wikipedia)
        : _wikipediaUriFromTag(wikipedia);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Uri? _wikipediaUriFromTag(String tag) {
    // OSM wikipedia tags look like "sl:Triglav".
    final parts = tag.split(':');
    if (parts.length < 2) return null;
    final lang = parts.first;
    final title = parts.sublist(1).join(':');
    return Uri.https('$lang.wikipedia.org', '/wiki/$title');
  }
}

/// The hairline this sheet divides its sections with — the same weight and
/// color as the rules on the peaks list, instead of Material's darker default.
class _SheetDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 0.5,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 10),
          // w500 label and a muted value, mirroring a peak row's name and
          // its height-and-range line.
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(
            value,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteTile extends StatelessWidget {
  final HikingRoute route;

  const _RouteTile({required this.route});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        // Weighted like a peak row, so a route in the sheet and a peak in the
        // list read as the same kind of thing to tap.
        title: Text(route.displayName, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(
          [
            if (route.difficulty != null) route.difficulty!,
            if (route.distanceM != null) '${(route.distanceM! / 1000).toStringAsFixed(1)} km',
          ].join('  |  '),
          style: TextStyle(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
        ),
        trailing: Icon(
          Icons.chevron_right,
          size: 20,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
        onTap: () => context.push('/route', extra: route),
      ),
    );
  }
}
