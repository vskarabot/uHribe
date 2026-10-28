import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../l10n/strings.dart';
import '../../models/nearby_filter.dart';
import '../../providers.dart';
import '../../services/location_service.dart';
import 'filter_sheet.dart';

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
    final nearby = ref.watch(selectedNearbyFilterProvider);

    void choose(String? area) {
      ref.read(selectedNearbyFilterProvider.notifier).set(null);
      ref.read(selectedMountainAreaProvider.notifier).set(area);
      Navigator.of(context).pop();
    }

    Future<void> chooseNearby() async {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text(Strings.locatingForNearby)));
      try {
        final position = await ref.read(locationServiceProvider).currentPosition();
        ref.read(selectedMountainAreaProvider.notifier).set(null);
        ref
            .read(selectedNearbyFilterProvider.notifier)
            .set(NearbyFilter(lat: position.lat, lon: position.lon));
        messenger.hideCurrentSnackBar();
      } on LocationException catch (e) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(_locationMessage(e.failure)),
            action: e.failure == LocationFailure.permissionDeniedForever
                ? const SnackBarAction(
                    label: Strings.openSettings,
                    onPressed: Geolocator.openAppSettings,
                  )
                : null,
          ));
      }
    }

    return FilterSheet(
      title: Strings.filterByArea,
      options: [
        FilterOption(
          label: Strings.allAreas,
          selected: selected == null && nearby == null,
          onTap: () => choose(null),
        ),
        FilterOption(
          label: Strings.filterNearby,
          selected: nearby != null,
          onTap: chooseNearby,
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

String _locationMessage(LocationFailure failure) => switch (failure) {
      LocationFailure.servicesDisabled => Strings.locationServicesDisabled,
      LocationFailure.permissionDenied => Strings.locationPermissionDenied,
      LocationFailure.permissionDeniedForever => Strings.locationPermissionDeniedForever,
      LocationFailure.unavailable => Strings.locationUnavailable,
    };
