import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' hide Position;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;

import '../../l10n/strings.dart';
import '../../models/elevation_bracket.dart';
import '../../models/nearby_filter.dart';
import '../../models/peak.dart';
import '../../providers.dart';
import '../../theme.dart';
import '../peaks/elevation_filter_sheet.dart';
import '../peaks/mountain_area_filter_sheet.dart';
import '../shell/offline_chip.dart';
import '../shell/pill_nav_bar.dart';
import 'peak_details_sheet.dart';
import 'peak_markers.dart';

final _sloveniaCenter = Point(coordinates: Position(14.9955, 46.1512));

final _initialViewport = CameraViewportState(center: _sloveniaCenter, zoom: 7.5);

const _peakFocusZoom = 14.5;

const _myLocationZoom = 12.0;

const _maxSearchResults = 6;

const _controlsGap = 12.0;

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  static const _sourceId = 'peaks';
  static const _clusterLayerId = 'clusters';
  static const _clusterCountLayerId = 'cluster-count';
  static const _unclusteredLayerId = 'unclustered-point';
  static const _unclusteredFilter = <Object>[
    '!',
    ['has', 'point_count'],
  ];

  MapboxMap? _map;
  bool _styleReady = false;
  bool _satellite = false;
  bool _interactionsAdded = false;
  double _bearing = 0;
  bool? _appliedLocationEnabled;
  List<Peak>? _lastRawPeaks;
  String? _lastArea;
  ElevationBracket? _lastElevation;
  NearbyFilter? _lastNearby;
  Set<int> _lastVisited = const {};
  bool _didInitialCenter = false;
  bool _cameraTakenOver = false;

  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<Peak> _visiblePeaks(
    List<Peak> peaks,
    String? area,
    ElevationBracket? elevation,
    NearbyFilter? nearby,
  ) {
    if (area == null && elevation == null && nearby == null) return peaks;
    return peaks.where((p) {
      if (area != null && p.mountainArea != area) return false;
      if (elevation != null && !elevation.matches(p.elevationM)) return false;
      if (nearby != null && !nearby.matches(p)) return false;
      return true;
    }).toList();
  }

  List<Peak> _searchMatches(List<Peak> visible) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final matches = visible
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            (p.nameAlt?.toLowerCase().contains(q) ?? false))
        .toList()
      ..sort((a, b) => (b.elevationM ?? 0).compareTo(a.elevationM ?? 0));
    return matches.length <= _maxSearchResults
        ? matches
        : matches.sublist(0, _maxSearchResults);
  }

  void _dismissSearch() {
    _searchFocus.unfocus();
    _searchController.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final peaksAsync = ref.watch(peaksProvider);
    final visitedIds = ref.watch(visitedPeakIdsProvider).value ?? const <int>{};
    final selectedArea = ref.watch(selectedMountainAreaProvider);
    final selectedElevation = ref.watch(selectedElevationBracketProvider);
    final selectedNearby = ref.watch(selectedNearbyFilterProvider);
    final locationEnabled =
        ref.watch(myProfileProvider).value?.locationEnabled ?? false;

    final navBarInset = MediaQuery.paddingOf(context).bottom;

    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final controlsInset = math.max(navBarInset, keyboardInset);

    final styleToggleTooltip =
        _satellite ? Strings.showOutdoorsMap : Strings.showSatelliteMap;

    final rawPeaks = peaksAsync.value;
    final peaks = rawPeaks == null
        ? null
        : _visiblePeaks(rawPeaks, selectedArea, selectedElevation, selectedNearby);
    final matches = peaks == null ? const <Peak>[] : _searchMatches(peaks);

    ref.listen(peakFocusProvider, (_, request) {
      if (request != null) _focusPeakById(request.peakId);
    });

    if (_styleReady && peaks != null) {
      final changed = !identical(rawPeaks, _lastRawPeaks) ||
          selectedArea != _lastArea ||
          selectedElevation != _lastElevation ||
          selectedNearby != _lastNearby ||
          !_setEquals(visitedIds, _lastVisited);
      if (changed) {
        _lastRawPeaks = rawPeaks;
        _lastArea = selectedArea;
        _lastElevation = selectedElevation;
        _lastNearby = selectedNearby;
        _lastVisited = visitedIds;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateSource(peaks, visitedIds);
        });
      }
    }

    if (_styleReady) _syncLocationComponent(locationEnabled);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Listener(
            onPointerDown: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            child: MapWidget(
              styleUri: MapboxStyles.OUTDOORS,
              viewport: _initialViewport,
              onMapCreated: _onMapCreated,
              onCameraChangeListener: _onCameraChanged,
              onStyleLoadedListener: (_) => _onStyleLoaded(
                  peaks ?? [], rawPeaks, selectedArea, selectedElevation, visitedIds),
            ),
          ),
          Positioned.fill(
            child: SafeArea(
              bottom: false,
              child: Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: EdgeInsets.only(
                    right: PillNavBar.horizontalMargin,
                    bottom: controlsInset + _controlsGap,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _CompassButton(
                        bearing: _bearing,
                        onPressed: _resetBearing,
                      ),
                      const SizedBox(height: _controlsGap),
                      _MapControlButton(
                        tooltip: styleToggleTooltip,
                        onPressed: _styleReady ? _toggleSatellite : null,
                        child: _ControlIcon(
                          _satellite
                              ? Icons.terrain_outlined
                              : Icons.satellite_alt_outlined,
                          enabled: _styleReady,
                        ),
                      ),
                      const SizedBox(height: _controlsGap),
                      _MapControlButton(
                        tooltip: Strings.showMyLocation,
                        onPressed: _goToMyLocation,
                        child: const _ControlIcon(Icons.my_location),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: ShadowedField(
                            child: TextField(
                              controller: _searchController,
                              focusNode: _searchFocus,
                              textInputAction: TextInputAction.search,
                              decoration: InputDecoration(
                                hintText: Strings.searchHint,
                                prefixIcon: const Icon(Icons.search, size: 20),
                                suffixIcon: _query.isNotEmpty
                                    ? IconButton(
                                        iconSize: 20,
                                        icon: const Icon(Icons.clear, size: 20),
                                        onPressed: _dismissSearch,
                                      )
                                    : null,
                              ),
                              onChanged: (v) => setState(() => _query = v),
                              onSubmitted: (_) {
                                if (matches.isNotEmpty) {
                                  _goToSearchResult(matches.first);
                                }
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const _FilterButton(),
                      ],
                    ),
                  ),
                  if (peaksAsync.isLoading)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: LinearProgressIndicator(),
                    ),
                  const Align(alignment: Alignment.center, child: OfflineChip()),
                  if (_query.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: _SearchResults(
                        peaks: matches,
                        onSelected: _goToSearchResult,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _setEquals(Set<int> a, Set<int> b) {
    if (a.length != b.length) return false;
    return a.every(b.contains);
  }

  Future<void> _onMapCreated(MapboxMap map) async {
    _map = map;
    await map.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
  }

  Future<void> _placeOrnaments(MapboxMap map) async {
    if (!mounted) return;
    final navBarInset = MediaQuery.paddingOf(context).bottom;
    final ornamentsBottom = navBarInset + _controlsGap;

    await map.compass.updateSettings(CompassSettings(enabled: false));
    await map.logo.updateSettings(LogoSettings(
      position: OrnamentPosition.BOTTOM_LEFT,
      marginLeft: PillNavBar.horizontalMargin,
      marginBottom: ornamentsBottom,
    ));
    await map.attribution.updateSettings(AttributionSettings(
      position: OrnamentPosition.BOTTOM_LEFT,
      marginLeft: PillNavBar.horizontalMargin + 92,
      marginBottom: ornamentsBottom,
    ));
  }

  void _onCameraChanged(CameraChangedEventData data) {
    final bearing = data.cameraState.bearing;
    if ((bearing - _bearing).abs() < 0.5) return;
    setState(() => _bearing = bearing);
  }

  Future<void> _resetBearing() async {
    await _map?.easeTo(CameraOptions(bearing: 0), MapAnimationOptions(duration: 300));
  }

  Future<void> _toggleSatellite() async {
    final map = _map;
    if (map == null) return;
    setState(() {
      _satellite = !_satellite;
      _styleReady = false;
    });
    await map.loadStyleURI(
      _satellite ? MapboxStyles.SATELLITE_STREETS : MapboxStyles.OUTDOORS,
    );
  }

  Future<void> _centerOnUserLocation() async {
    if (_didInitialCenter || _cameraTakenOver) return;
    _didInitialCenter = true;

    if (!await _hasLocationPermission()) return;

    Position? position;
    try {
      final cached = await Geolocator.getLastKnownPosition();
      final fix = cached ?? await Geolocator.getCurrentPosition();
      position = Position(fix.longitude, fix.latitude);
    } catch (_) {
      return;
    }

    final map = _map;
    if (map == null || !mounted || _cameraTakenOver) return;
    await map.setCamera(
      CameraOptions(center: Point(coordinates: position), zoom: _myLocationZoom),
    );
  }

  Future<void> _onStyleLoaded(
    List<Peak> peaks,
    List<Peak>? rawPeaks,
    String? area,
    ElevationBracket? elevation,
    Set<int> visitedIds,
  ) async {
    final map = _map;
    if (map == null) return;

    await map.style.addSource(GeoJsonSource(
      id: _sourceId,
      data: jsonEncode(_toFeatureCollection(peaks, visitedIds)),
      cluster: true,
      clusterRadius: 50,
      clusterMaxZoom: 13,
    ));

    await map.style.addLayer(CircleLayer(
      id: _clusterLayerId,
      sourceId: _sourceId,
      filter: ['has', 'point_count'],
      circleColorExpression: [
        'step',
        ['get', 'point_count'],
        '#2F6B4F',
        25,
        '#1F4D38',
        100,
        '#12331F',
      ],
      circleRadiusExpression: [
        'step',
        ['get', 'point_count'],
        16.0,
        25,
        20.0,
        100,
        26.0,
      ],
      circleStrokeWidth: 2,
      circleStrokeColor: Colors.white.toARGB32(),
    ));

    await map.style.addLayer(SymbolLayer(
      id: _clusterCountLayerId,
      sourceId: _sourceId,
      filter: ['has', 'point_count'],
      textFieldExpression: ['get', 'point_count_abbreviated'],
      textSize: 13,
      textColor: Colors.white.toARGB32(),
      textAllowOverlap: true,
      textIgnorePlacement: true,
    ));

    await hideStylePeakLabels(map.style);
    await addPeakMarkerImages(map.style);
    await map.style.addLayer(peakMarkerLayer(
      id: _unclusteredLayerId,
      sourceId: _sourceId,
      filter: _unclusteredFilter,
    ));

    if (!_interactionsAdded) _addInteractions(map);
    await _placeOrnaments(map);

    _styleReady = true;
    _lastRawPeaks = rawPeaks;
    _lastArea = area;
    _lastElevation = elevation;
    _lastVisited = visitedIds;
    if (mounted) setState(() {});

    await _centerOnUserLocation();
  }

  void _addInteractions(MapboxMap map) {
    _interactionsAdded = true;

    map.addInteraction(
      TapInteraction(
        FeaturesetDescriptor(layerId: _unclusteredLayerId),
        (feature, _) {
          final peakId = feature.properties['peakId'];
          if (peakId is num) {
            _focusPeakById(peakId.toInt());
          }
        },
      ),
      interactionID: 'tap_peak',
    );

    map.addInteraction(
      TapInteraction(
        FeaturesetDescriptor(layerId: _clusterLayerId),
        (feature, context) async {
          final current = await map.getCameraState();
          await map.flyTo(
            CameraOptions(center: context.point, zoom: current.zoom + 2),
            MapAnimationOptions(duration: 400),
          );
        },
      ),
      interactionID: 'tap_cluster',
    );
  }

  Future<void> _updateSource(List<Peak> peaks, Set<int> visitedIds) async {
    final map = _map;
    if (map == null) return;
    final source = await map.style.getSource(_sourceId);
    if (source is GeoJsonSource) {
      await source.updateGeoJSON(jsonEncode(_toFeatureCollection(peaks, visitedIds)));
    }
  }

  Map<String, dynamic> _toFeatureCollection(List<Peak> peaks, Set<int> visitedIds) {
    return {
      'type': 'FeatureCollection',
      'features': peaks
          .map((p) => {
                'type': 'Feature',
                'properties': {
                  'peakId': p.id,
                  'name': p.name,
                  'ele': ?p.elevationM,
                  'visited': visitedIds.contains(p.id),
                },
                'geometry': {
                  'type': 'Point',
                  'coordinates': [p.lon, p.lat],
                },
              })
          .toList(),
    };
  }

  void _goToSearchResult(Peak peak) {
    _dismissSearch();
    _focusPeakById(peak.id);
  }

  Future<void> _focusPeakById(int peakId) async {
    _cameraTakenOver = true;
    final peaks = ref.read(peaksProvider).value;
    if (peaks == null) return;
    Peak? peak;
    for (final p in peaks) {
      if (p.id == peakId) {
        peak = p;
        break;
      }
    }
    if (peak == null) return;

    final map = _map;
    if (map != null) {
      await map.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(peak.lon, peak.lat)),
          zoom: _peakFocusZoom,
        ),
        MapAnimationOptions(duration: 600),
      );
    }

    if (!mounted) return;
    await showPeakDetailsSheet(context, peakId);
  }

  void _syncLocationComponent(bool enabled) {
    if (_appliedLocationEnabled == enabled) return;
    _appliedLocationEnabled = enabled;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final map = _map;
      if (map == null || !mounted) return;
      final show = enabled && await _hasLocationPermission();
      await map.location.updateSettings(
        LocationComponentSettings(enabled: show, pulsingEnabled: show),
      );
    });
  }

  Future<bool> _hasLocationPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  Future<void> _goToMyLocation() async {
    _cameraTakenOver = true;
    final map = _map;
    if (map == null) return;

    if (!await Geolocator.isLocationServiceEnabled()) {
      _showLocationMessage(Strings.locationServicesDisabled);
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      _showLocationMessage(
        Strings.locationPermissionDeniedForever,
        openSettings: true,
      );
      return;
    }
    if (permission == LocationPermission.denied) {
      _showLocationMessage(Strings.locationPermissionDenied);
      return;
    }

    if (!mounted) return;

    await rememberLocationEnabled(ref, true);

    _appliedLocationEnabled = true;
    await map.location.updateSettings(
      LocationComponentSettings(enabled: true, pulsingEnabled: true),
    );

    final Position position;
    try {
      final fix = await Geolocator.getCurrentPosition();
      position = Position(fix.longitude, fix.latitude);
    } catch (_) {
      _showLocationMessage(Strings.locationUnavailable);
      return;
    }

    await map.flyTo(
      CameraOptions(center: Point(coordinates: position), zoom: _myLocationZoom),
      MapAnimationOptions(duration: 800),
    );
  }

  void _showLocationMessage(String message, {bool openSettings = false}) {
    if (!mounted) return;
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
}

class _MapControlButton extends StatelessWidget {
  const _MapControlButton({
    required this.tooltip,
    required this.onPressed,
    required this.child,
  });

  static const size = 48.0;
  static const _discSize = 43.0;

  final String tooltip;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0x4DF7F7F7),
      ),
      child: Center(
        child: Tooltip(
          message: tooltip,
          child: Material(
            color: Colors.black,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: SizedBox.square(dimension: _discSize, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class _ControlIcon extends StatelessWidget {
  const _ControlIcon(this.icon, {this.enabled = true});

  final IconData icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Icon(icon, size: 22, color: enabled ? Colors.white : Colors.white38);
  }
}

class _CompassButton extends StatelessWidget {
  const _CompassButton({required this.bearing, required this.onPressed});

  final double bearing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final north = bearing.abs() < 0.5 || (360 - bearing.abs()) < 0.5;
    return IgnorePointer(
      ignoring: north,
      child: AnimatedOpacity(
        opacity: north ? 0 : 1,
        duration: const Duration(milliseconds: 200),
        child: _MapControlButton(
          tooltip: Strings.resetNorth,
          onPressed: onPressed,
          child: Transform.rotate(
            angle: -bearing * math.pi / 180,
            child: const CustomPaint(painter: _CompassNeedlePainter()),
          ),
        ),
      ),
    );
  }
}

class _CompassNeedlePainter extends CustomPainter {
  const _CompassNeedlePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const halfWidth = 5.4;
    const length = 12.0;
    const gap = 0.8;

    final north = Path()
      ..moveTo(c.dx, c.dy - length)
      ..lineTo(c.dx + halfWidth, c.dy - gap)
      ..lineTo(c.dx - halfWidth, c.dy - gap)
      ..close();
    final south = Path()
      ..moveTo(c.dx, c.dy + length)
      ..lineTo(c.dx + halfWidth, c.dy + gap)
      ..lineTo(c.dx - halfWidth, c.dy + gap)
      ..close();

    canvas.drawPath(north, Paint()..color = const Color(0xFFF67E64));
    canvas.drawPath(south, Paint()..color = const Color(0xFFFCFCFC));
  }

  @override
  bool shouldRepaint(_CompassNeedlePainter oldDelegate) => false;
}

class _FilterButton extends ConsumerWidget {
  const _FilterButton();

  static const _size = 48.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final active = ref.watch(selectedMountainAreaProvider) != null ||
        ref.watch(selectedElevationBracketProvider) != null ||
        ref.watch(selectedNearbyFilterProvider) != null;

    return ShadowedField(
      radius: _size / 2,
      child: Material(
        color: active
            ? colorScheme.secondaryContainer
            : colorScheme.surfaceContainerLowest,
        shape: CircleBorder(
          side: active
              ? BorderSide(color: colorScheme.primary.withValues(alpha: 0.35))
              : AppTheme.fieldBorder(colorScheme),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showModalBottomSheet(
            context: context,
            showDragHandle: true,
            builder: (_) => const _FiltersSheet(),
          ),
          child: SizedBox.square(
            dimension: _size,
            child: Tooltip(
              message: Strings.filters,
              child: Icon(
                Icons.filter_alt_outlined,
                color: active ? colorScheme.onSecondaryContainer : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FiltersSheet extends ConsumerWidget {
  const _FiltersSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final area = ref.watch(selectedMountainAreaProvider);
    final elevation = ref.watch(selectedElevationBracketProvider);
    final nearby = ref.watch(selectedNearbyFilterProvider);

    final divider = Divider(
      height: 1,
      thickness: 0.5,
      indent: 16,
      endIndent: 16,
      color: colorScheme.outlineVariant,
    );

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              Strings.filters,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          Divider(height: 1, thickness: 0.5, color: colorScheme.outlineVariant),
          _FilterRow(
            icon: Icons.filter_alt_outlined,
            title: Strings.filterByArea,
            value: nearby != null ? Strings.filterNearby : area ?? Strings.allAreas,
            active: area != null || nearby != null,
            onTap: () => showMountainAreaFilterSheet(context),
            onClear: () {
              ref.read(selectedMountainAreaProvider.notifier).set(null);
              ref.read(selectedNearbyFilterProvider.notifier).set(null);
            },
          ),
          divider,
          _FilterRow(
            icon: Icons.height,
            title: Strings.filterByElevation,
            value: elevation?.label ?? Strings.allElevations,
            active: elevation != null,
            onTap: () => showElevationFilterSheet(context),
            onClear: () =>
                ref.read(selectedElevationBracketProvider.notifier).set(null),
          ),
          if (area != null || elevation != null || nearby != null) ...[
            divider,
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: OutlinedButton(
                onPressed: () => clearPeakFilters(ref),
                child: const Text(Strings.clearFilters),
              ),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.active,
    required this.onTap,
    required this.onClear,
  });

  final IconData icon;
  final String title;
  final String value;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: active ? colorScheme.primary : null),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: active ? FontWeight.w700 : null,
          color: active ? colorScheme.primary : colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: active
          ? IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: Strings.clearFilters,
              onPressed: onClear,
            )
          : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.peaks, required this.onSelected});

  final List<Peak> peaks;
  final ValueChanged<Peak> onSelected;

  static const _maxHeight = 268.0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(AppTheme.panelRadius);

    return ShadowedField(
      radius: AppTheme.panelRadius,
      child: Material(
        color: colorScheme.surfaceContainerLowest,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: AppTheme.fieldBorder(colorScheme),
        ),
        child: peaks.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Text(
                  Strings.noPeaksFound,
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              )
            : ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: _maxHeight),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: peaks.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    thickness: 0.5,
                    indent: 16,
                    endIndent: 16,
                    color: colorScheme.outlineVariant,
                  ),
                  itemBuilder: (context, index) {
                    final peak = peaks[index];
                    return ListTile(
                      dense: true,
                      leading: Icon(Icons.place_outlined, size: 20, color: colorScheme.primary),
                      title: Text(
                        peak.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: peak.elevationM == null
                          ? null
                          : Text(
                              '${peak.elevationM} m',
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                              ),
                            ),
                      onTap: () => onSelected(peak),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
