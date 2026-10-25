import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' hide Position;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;

import '../../l10n/strings.dart';
import '../../models/elevation_bracket.dart';
import '../../models/peak.dart';
import '../../providers.dart';
import '../../theme.dart';
import '../peaks/peak_filter_chips.dart';
import '../shell/offline_chip.dart';
import '../shell/pill_nav_bar.dart';
import 'peak_details_sheet.dart';

/// Slovenia's rough geographic center, used as the initial camera target.
final _sloveniaCenter = Point(coordinates: Position(14.9955, 46.1512));

/// Held as a single instance rather than built inside `build`: MapWidget
/// re-applies its viewport whenever the new one isn't `==` the old, and
/// ViewportState has no value equality — a fresh instance per build would
/// yank the camera back to the country view every time a provider settles.
final _initialViewport = CameraViewportState(center: _sloveniaCenter, zoom: 7.5);

/// Zoom level used when centering on a single peak — close enough to see its
/// immediate surroundings.
const _peakFocusZoom = 14.5;

/// Zoom level used when centering on the user, whether on load or from the
/// locate button — wide enough to show which peaks are within reach.
const _myLocationZoom = 12.0;

/// How many search suggestions the map offers at once. The panel floats over
/// the map, so it has to stay a hint about where to go rather than grow into
/// a second peak list covering the thing you're searching.
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
  static const _unclusteredIconLayerId = 'unclustered-point-icon';

  MapboxMap? _map;
  bool _styleReady = false;
  bool _satellite = false;
  bool _interactionsAdded = false;
  double _bearing = 0;
  // The location-component state we last pushed to the map, so a rebuild
  // doesn't re-run the permission check and settings call on every frame.
  bool? _appliedLocationEnabled;
  // Tracks the raw (unfiltered) peaks list and the filters, not the filtered
  // list — the filtered list is a fresh object on every build, so comparing
  // against it directly would never detect "nothing actually changed".
  List<Peak>? _lastRawPeaks;
  String? _lastArea;
  ElevationBracket? _lastElevation;
  Set<int> _lastVisited = const {};
  // The on-load centering runs once per map, and loses to anything that aims
  // the camera deliberately (a peak focus, the locate button) — including a
  // takeover that lands while a slow first fix is still resolving.
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

  /// The peaks the map is currently drawing — everything the two filters let
  /// through. Search runs over this same set, so a suggestion always
  /// corresponds to a pin the user can actually see.
  List<Peak> _visiblePeaks(
    List<Peak> peaks,
    String? area,
    ElevationBracket? elevation,
  ) {
    if (area == null && elevation == null) return peaks;
    return peaks.where((p) {
      if (area != null && p.mountainArea != area) return false;
      if (elevation != null && !elevation.matches(p.elevationM)) return false;
      return true;
    }).toList();
  }

  /// The suggestions for the current query: tallest first, same as the list
  /// screen orders its results, and capped at [_maxSearchResults].
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

  /// Dismisses the search — the map is about to fly somewhere, and a panel
  /// of suggestions left open would cover the peak they just picked.
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
    final locationEnabled =
        ref.watch(myProfileProvider).value?.locationEnabled ?? false;

    // The home shell's floating pill nav bar sits over the map (the shell
    // uses extendBody), and Scaffold reports its height as bottom padding —
    // so offset the controls by it instead of hard-coding the pill's size.
    final navBarInset = MediaQuery.paddingOf(context).bottom;

    // The map keeps its full height with the keyboard up, so nothing moves
    // the locate button out from under it — it has to step over the keyboard
    // itself. The nav bar is behind the keyboard at that point, so it's one
    // or the other, never both.
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final controlsInset = math.max(navBarInset, keyboardInset);

    final styleToggleTooltip =
        _satellite ? Strings.showOutdoorsMap : Strings.showSatelliteMap;

    final rawPeaks = peaksAsync.value;
    final peaks = rawPeaks == null
        ? null
        : _visiblePeaks(rawPeaks, selectedArea, selectedElevation);
    final matches = peaks == null ? const <Peak>[] : _searchMatches(peaks);

    // A peak was selected elsewhere (e.g. the peak list) — fly to it and
    // show its details once we know about it.
    ref.listen(peakFocusProvider, (_, request) {
      if (request != null) _focusPeakById(request.peakId);
    });

    // Whenever peaks or the visited set change (and the style is ready),
    // push the latest GeoJSON into the source.
    if (_styleReady && peaks != null) {
      final changed = !identical(rawPeaks, _lastRawPeaks) ||
          selectedArea != _lastArea ||
          selectedElevation != _lastElevation ||
          !_setEquals(visitedIds, _lastVisited);
      if (changed) {
        _lastRawPeaks = rawPeaks;
        _lastArea = selectedArea;
        _lastElevation = selectedElevation;
        _lastVisited = visitedIds;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateSource(peaks, visitedIds);
        });
      }
    }

    if (_styleReady) _syncLocationComponent(locationEnabled);

    return Scaffold(
      // The keyboard slides over the map instead of squeezing it: resizing
      // would re-lay-out the platform view and shift the camera under the
      // user mid-search, so the place they were looking at moves while they
      // type the name of the place they were looking for.
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // A Listener, not a GestureDetector: the map is a platform view and
          // wins every gesture arena it's in, so a detector wrapped around it
          // never fires. Raw pointer events are delivered to the whole hit-test
          // path regardless of who goes on to claim the gesture, which is all
          // this needs — touch the map, the keyboard goes away.
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
                  // Aligned to the nav pill's gutter rather than the map's
                  // own 16, so the button and the bar directly beneath it
                  // share one right edge instead of stepping apart.
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
          // The controls float straight on the map: no panel, no tint, no
          // blur behind them. Anything laid across the top to sit them on has
          // an edge where it stops, and that line reads as damage to the map.
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
                    // Its own shadow, as on the list screen: with nothing laid
                    // under it, the field has to lift itself off the terrain
                    // or it reads as part of the map.
                    child: ShadowedField(
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocus,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: Strings.searchHint,
                          // InputDecorator sizes its own icons rather than
                          // deferring to the global icon theme.
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
                        // Enter on the single best match is the whole gesture
                        // for someone who typed the full name.
                        onSubmitted: (_) {
                          if (matches.isNotEmpty) {
                            _goToSearchResult(matches.first);
                          }
                        },
                      ),
                    ),
                  ),
                  if (peaksAsync.isLoading)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: LinearProgressIndicator(),
                    ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: PeakFilterChips(),
                  ),
                  // The shell hides its own top-center chip on this tab and
                  // lets the map place it here instead: pinned to the top it
                  // sat on the search field, and the first clear strip of map
                  // is the one below the filters.
                  const Align(alignment: Alignment.center, child: OfflineChip()),
                  if (_query.trim().isNotEmpty)
                    Padding(
                      // The results are a transient answer to what was typed,
                      // so they hang under the field rather than growing the
                      // block of controls by 250px on every keystroke.
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

  /// Moves the camera to wherever the user is as soon as the map comes up, so
  /// they open onto their own surroundings rather than the whole country.
  ///
  /// Silent by design: it only uses access the OS has already granted and
  /// never prompts — asking for location the moment a map appears, with no
  /// tap behind it, is what the locate button and the profile toggle are for.
  /// Without that grant the camera just stays on [_sloveniaCenter].
  Future<void> _centerOnUserLocation() async {
    if (_didInitialCenter || _cameraTakenOver) return;
    _didInitialCenter = true;

    if (!await _hasLocationPermission()) return;

    // The last known fix comes back immediately, so the map settles into
    // place instead of sitting on the country view through a cold GNSS start.
    // Only fall back to a live fix when the OS has nothing cached.
    Position? position;
    try {
      final cached = await Geolocator.getLastKnownPosition();
      final fix = cached ?? await Geolocator.getCurrentPosition();
      position = Position(fix.longitude, fix.latitude);
    } catch (_) {
      // No fix available — the country view is a fine place to start, and the
      // locate button is there to explain itself if they ask for one.
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
      // Colors inside style-spec expressions must be hex strings, unlike
      // the plain `circleColor` property (which takes an ARGB int).
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

    await map.style.addLayer(CircleLayer(
      id: _unclusteredLayerId,
      sourceId: _sourceId,
      filter: [
        '!',
        ['has', 'point_count'],
      ],
      circleColorExpression: [
        'case',
        ['get', 'visited'],
        '#2F6B4F',
        '#E07A2C',
      ],
      // Sized to sit behind and fully contain the mountain glyph below, so
      // the two read as one badge instead of two overlapping icons.
      circleRadius: 13,
      circleStrokeWidth: 1.5,
      circleStrokeColor: Colors.white.toARGB32(),
    ));

    // 'mountain' ships in the Outdoors style's own sprite sheet, so it draws
    // as a hill glyph on top of the colored circle with no custom image
    // registration needed — addStyleImage's platform channel is unreliable
    // on Android in this mapbox_maps_flutter version (a known upstream
    // issue: github.com/mapbox/mapbox-maps-flutter/issues/978), and losing
    // that call would silently drop peaks off the map entirely. Sized small
    // enough to nest inside the circle above rather than spill past its
    // edge, which is what made the two layers read as duplicate icons.
    await map.style.addLayer(SymbolLayer(
      id: _unclusteredIconLayerId,
      sourceId: _sourceId,
      filter: [
        '!',
        ['has', 'point_count'],
      ],
      iconImage: 'mountain',
      iconSize: 0.55,
      iconAllowOverlap: true,
      iconIgnorePlacement: true,
    ));

    if (!_interactionsAdded) _addInteractions(map);
    await _placeOrnaments(map);

    _styleReady = true;
    _lastRawPeaks = rawPeaks;
    _lastArea = area;
    _lastElevation = elevation;
    _lastVisited = visitedIds;
    if (mounted) setState(() {});

    // Centering waits until here rather than running from onMapCreated: at
    // creation the platform view isn't guaranteed to be laid out yet, and
    // setCamera on an unsized view is dropped. By style load it has a size.
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

  /// Handles a tap on a search suggestion: clears the search out of the way,
  /// then hands off to the same fly-and-open path the pins and the peak list
  /// use, so arriving at a peak looks identical however you got there.
  void _goToSearchResult(Peak peak) {
    _dismissSearch();
    _focusPeakById(peak.id);
  }

  /// Flies the camera to peak [peakId]'s location, zoomed in close, then
  /// shows its details in a bottom sheet. Looks the peak up in the
  /// already-loaded list, so it's a no-op if peaks haven't loaded yet.
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

  /// Mirrors the user's stored location preference onto the map's location
  /// component, so someone who already opted in sees the puck as soon as the
  /// map loads instead of being prompted again.
  void _syncLocationComponent(bool enabled) {
    if (_appliedLocationEnabled == enabled) return;
    _appliedLocationEnabled = enabled;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final map = _map;
      if (map == null || !mounted) return;
      // The preference only records that the user opted in — the OS grant is
      // still the source of truth, and they can revoke it at any time. Check
      // it silently here; only the button ever prompts.
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

    // Remember the opt-in so later sessions can skip straight to showing the
    // puck. Best-effort: a failed write shouldn't block this tap.
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

/// Stands in for the Mapbox compass, whose native placement wouldn't line up
/// with the buttons below it. Keeps its space while hidden so they don't jump.
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

/// The Mapbox compass's needle: a coral north half and a white south half.
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

/// The suggestion panel under the map's search field.
///
/// Styled as a continuation of the field above it — same radius, same lifted
/// white, same shadow — so the two read as one control rather than a list
/// that happened to land on the map.
class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.peaks, required this.onSelected});

  final List<Peak> peaks;
  final ValueChanged<Peak> onSelected;

  /// Tall enough for the full [_maxSearchResults], short enough that the map
  /// stays the larger half of the screen.
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
        // Radius via `shape` rather than `borderRadius` — Material asserts if
        // it's handed both, and the hairline has to come from the shape.
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.7)),
        ),
        child: peaks.isEmpty
            // The filters sit directly above, so a search that finds nothing
            // usually means one of them is hiding the peak — the chips are
            // already the visible way out, no extra button needed here.
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
