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

Future<void> showPeakDetailsSheet(BuildContext context, int peakId) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
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
                          Text(
                            peak.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              height: 1.15,
                            ),
                          ),
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
                const SizedBox(height: 20),
                FilledButton.icon(
                  icon: const Icon(Icons.flag),
                  label: const Text(Strings.checkIn),
                  onPressed: () => _checkIn(context, ref, peak),
                ),
                const SizedBox(height: 22),
                _SheetDivider(),
                const SizedBox(height: 16),
                _SectionTitle(Strings.detailsTitle),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.place_outlined,
                      size: 16,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${peak.lat.toStringAsFixed(5)}, ${peak.lon.toStringAsFixed(5)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
                if (peak.description != null && peak.description!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(peak.description!),
                ],
                const SizedBox(height: 22),
                _SheetDivider(),
                const SizedBox(height: 16),
                _SectionTitle(Strings.routesTitle),
                const SizedBox(height: 8),
                routesAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, _) => const Text(Strings.loadError),
                  data: (routes) {
                    if (routes.isEmpty) {
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
    Navigator.of(context).pop();

    if (outcome != null) {
      await ref.read(pendingCheckInsProvider.notifier).reload();
      if (outcome.status == CheckInStatus.recorded) {
        invalidateUserData(ref);
      }
      if (!context.mounted) return;
      _snack(context, switch (outcome.status) {
        CheckInStatus.recorded => Strings.checkInRecorded,
        CheckInStatus.queued => Strings.checkInQueued,
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
    final parts = tag.split(':');
    if (parts.length < 2) return null;
    final lang = parts.first;
    final title = parts.sublist(1).join(':');
    return Uri.https('$lang.wikipedia.org', '/wiki/$title');
  }
}

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

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurface,
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
