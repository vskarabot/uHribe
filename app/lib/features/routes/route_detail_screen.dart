import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../l10n/strings.dart';
import '../../models/hiking_route.dart';

class RouteDetailScreen extends StatefulWidget {
  final HikingRoute route;

  const RouteDetailScreen({super.key, required this.route});

  @override
  State<RouteDetailScreen> createState() => _RouteDetailScreenState();
}

class _RouteDetailScreenState extends State<RouteDetailScreen> {
  static const _sourceId = 'route-line-source';
  static const _layerId = 'route-line-layer';
  static const _demSourceId = 'mapbox-dem';
  static const _skyLayerId = 'sky';

  static const _demTileset = 'mapbox://mapbox.mapbox-terrain-dem-v1';

  static const _terrainExaggeration = 1.4;
  static const _pitch3d = 65.0;

  static const _elevationSampleBudget = 120;

  MapboxMap? _map;
  List<Point> _coordinates = const [];
  bool _terrainEnabled = true;
  bool _styleReady = false;
  bool _sampled = false;
  _RouteRelief? _relief;

  bool _reliefResolved = false;

  Future<void> _onMapCreated(MapboxMap map) async {
    _map = map;
    await map.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
  }

  Future<void> _onStyleLoaded(StyleLoadedEventData _) async {
    final map = _map;
    if (map == null || _styleReady) return;

    final geometry = jsonDecode(widget.route.geojson) as Map<String, dynamic>;
    final feature = {
      'type': 'Feature',
      'properties': <String, dynamic>{},
      'geometry': geometry,
    };

    await map.style.addSource(RasterDemSource(
      id: _demSourceId,
      url: _demTileset,
      tileSize: 514,
    ));
    await map.style.addSource(GeoJsonSource(id: _sourceId, data: jsonEncode(feature)));

    await map.style.addLayer(LineLayer(
      id: _layerId,
      sourceId: _sourceId,
      lineColor: Colors.deepOrange.toARGB32(),
      lineWidth: 5,
      lineBorderColor: Colors.white.toARGB32(),
      lineBorderWidth: 1.5,
      lineCap: LineCap.ROUND,
      lineJoin: LineJoin.ROUND,
    ));

    await map.style.addLayer(SkyLayer(
      id: _skyLayerId,
      skyType: SkyType.ATMOSPHERE,
      skyAtmosphereSun: [0.0, 90.0],
      skyAtmosphereSunIntensity: 15,
    ));

    _styleReady = true;
    await _applyTerrain(enabled: _terrainEnabled);

    _coordinates = _extractCoordinates(geometry);
    if (_coordinates.isEmpty) return;

    await _frameRoute(pitch: 0, bearing: 0);
  }

  Future<void> _applyTerrain({required bool enabled}) async {
    final map = _map;
    if (map == null || !_styleReady) return;

    await map.style.setStyleTerrain(jsonEncode({
      'source': _demSourceId,
      'exaggeration': enabled ? _terrainExaggeration : 0,
    }));
  }

  Future<void> _frameRoute({required double pitch, required double bearing}) async {
    final map = _map;
    if (map == null || _coordinates.isEmpty) return;

    final camera = await map.cameraForCoordinatesPadding(
      _coordinates,
      CameraOptions(pitch: pitch, bearing: bearing),
      MbxEdgeInsets(
        top: pitch > 0 ? 140 : 40,
        left: 32,
        bottom: pitch > 0 ? 80 : 40,
        right: 32,
      ),
      null,
      null,
    );
    await map.flyTo(camera, MapAnimationOptions(duration: 900));
  }

  Future<void> _onMapIdle(MapIdleEventData _) async {
    if (_sampled || !_terrainEnabled || _coordinates.isEmpty) return;
    _sampled = true;

    final map = _map;
    if (map == null) return;

    final samples = _sampleTargets();
    final elevations = await Future.wait(
      samples.map((p) => map.getElevation(p).catchError((_) => null)),
    );

    _RouteRelief? relief;
    Point? lowest;
    Point? highest;
    double? minM;
    double? maxM;

    for (var i = 0; i < samples.length; i++) {
      final e = elevations[i];
      if (e == null) continue;
      if (minM == null || e < minM) {
        minM = e;
        lowest = samples[i];
      }
      if (maxM == null || e > maxM) {
        maxM = e;
        highest = samples[i];
      }
    }

    final resolved = elevations.where((e) => e != null).length;
    if (minM != null && maxM != null && resolved >= samples.length ~/ 2) {
      relief = _RouteRelief(
        minM: minM.round(),
        maxM: maxM.round(),
        gainM: (maxM - minM).round(),
      );
    }

    if (!mounted) return;
    setState(() {
      _relief = relief;
      _reliefResolved = true;
    });

    final bearing = (lowest != null && highest != null && lowest != highest)
        ? _bearingBetween(lowest, highest)
        : 0.0;
    await _frameRoute(pitch: _pitch3d, bearing: bearing);
  }

  List<Point> _sampleTargets() {
    if (_coordinates.length <= _elevationSampleBudget) return _coordinates;

    final stride = _coordinates.length / _elevationSampleBudget;
    final picked = <Point>[];
    for (var i = 0; i < _elevationSampleBudget; i++) {
      picked.add(_coordinates[(i * stride).floor()]);
    }
    picked.add(_coordinates.last);
    return picked;
  }

  Future<void> _setTerrain(bool enabled) async {
    if (enabled == _terrainEnabled) return;
    setState(() => _terrainEnabled = enabled);
    await _applyTerrain(enabled: enabled);
    await _frameRoute(pitch: enabled ? _pitch3d : 0, bearing: 0);
  }

  double _bearingBetween(Point from, Point to) {
    final lat1 = _degToRad(from.coordinates.lat.toDouble());
    final lat2 = _degToRad(to.coordinates.lat.toDouble());
    final dLon = _degToRad(to.coordinates.lng.toDouble() - from.coordinates.lng.toDouble());

    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return (_radToDeg(math.atan2(y, x)) + 360) % 360;
  }

  double _degToRad(double deg) => deg * (math.pi / 180);
  double _radToDeg(double rad) => rad * (180 / math.pi);

  List<Point> _extractCoordinates(Map<String, dynamic> geometry) {
    final type = geometry['type'] as String?;
    final coords = geometry['coordinates'];
    final points = <Point>[];

    void addLine(List line) {
      for (final c in line) {
        final pair = c as List;
        points.add(Point(coordinates: Position(
          (pair[0] as num).toDouble(),
          (pair[1] as num).toDouble(),
        )));
      }
    }

    if (type == 'MultiLineString') {
      for (final line in coords as List) {
        addLine(line as List);
      }
    } else if (type == 'LineString') {
      addLine(coords as List);
    }
    return points;
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.route;
    final relief = _relief;

    return Scaffold(
      appBar: AppBar(
        title: Text(route.displayName),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('2D'),
                  tooltip: Strings.routeShow2d,
                ),
                ButtonSegment(
                  value: true,
                  label: Text('3D'),
                  tooltip: Strings.routeShow3d,
                ),
              ],
              selected: {_terrainEnabled},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => _setTerrain(selection.first),
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: MapWidget(
              styleUri: MapboxStyles.OUTDOORS,
              onMapCreated: _onMapCreated,
              onStyleLoadedListener: _onStyleLoaded,
              onMapIdleListener: _onMapIdle,
            ),
          ),
          _RouteSummaryPanel(
            route: route,
            relief: relief,
            reliefPending: relief == null && _terrainEnabled && !_reliefResolved,
          ),
        ],
      ),
    );
  }
}

class _RouteSummaryPanel extends StatelessWidget {
  final HikingRoute route;
  final _RouteRelief? relief;
  final bool reliefPending;

  const _RouteSummaryPanel({
    required this.route,
    required this.relief,
    required this.reliefPending,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final showRelief = relief != null || reliefPending;

    final stats = <Widget>[
      if (route.distanceM != null)
        _StatTile(
          icon: Icons.straighten,
          label: Strings.routeDistance,
          value: (route.distanceM! / 1000).toStringAsFixed(1),
          unit: 'km',
        ),
      if (showRelief)
        _StatTile(
          icon: Icons.trending_up,
          label: Strings.routeElevationGain,
          value: relief == null ? null : '${relief!.gainM}',
          unit: 'm',
        ),
      if (showRelief)
        _StatTile(
          icon: Icons.landscape_outlined,
          label: Strings.routeHighestPoint,
          value: relief == null ? null : '${relief!.maxM}',
          unit: 'm',
        ),
    ];

    final hasEndpoints = route.fromName != null || route.toName != null;
    final hasFooter = hasEndpoints || route.difficulty != null;
    if (stats.isEmpty && !hasFooter) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(color: colorScheme.outline.withValues(alpha: 0.4)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (stats.isNotEmpty)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < stats.length; i++) ...[
                        if (i > 0)
                          VerticalDivider(
                            width: 24,
                            thickness: 1,
                            color: colorScheme.outline.withValues(alpha: 0.35),
                          ),
                        Expanded(child: stats[i]),
                      ],
                    ],
                  ),
                ),
              if (stats.isNotEmpty && hasFooter) const SizedBox(height: 14),
              if (hasFooter)
                Row(
                  children: [
                    if (hasEndpoints)
                      Expanded(child: _Endpoints(route: route))
                    else
                      const Spacer(),
                    if (route.difficulty != null) ...[
                      const SizedBox(width: 12),
                      _DifficultyPill(difficulty: route.difficulty!),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final String unit;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final pending = value == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                value ?? '–',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                  color: pending
                      ? colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                      : colorScheme.onSurface,
                ),
              ),
            ),
            if (!pending) ...[
              const SizedBox(width: 3),
              Text(
                unit,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(icon, size: 13, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Endpoints extends StatelessWidget {
  final HikingRoute route;

  const _Endpoints({required this.route});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final style = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: colorScheme.onSurface,
    );

    return Row(
      children: [
        Icon(Icons.trip_origin, size: 13, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            route.fromName ?? '–',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        const SizedBox(width: 6),
        Icon(Icons.arrow_right_alt, size: 16, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            route.toName ?? '–',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }
}

class _DifficultyPill extends StatelessWidget {
  final String difficulty;

  const _DifficultyPill({required this.difficulty});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: Strings.routeDifficulty,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          difficulty,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}

class _RouteRelief {
  final int minM;
  final int maxM;
  final int gainM;

  const _RouteRelief({required this.minM, required this.maxM, required this.gainM});
}
