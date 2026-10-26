import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;

const _slate = Color(0xFF37474F);
const _visitedColor = Color(0xFF2F6B4F);
const _labelColor = Color(0xFF263238);
const _pixelRatio = 3.0;
const _badgeSize = Size(22, 22);
const _badgeIcon = 'peak-badge';

Future<void> addPeakMarkerImages(StyleManager style) async {
  await _addBadge(
    style,
    _badgeIcon,
    fill: Colors.white,
    border: _slate.withValues(alpha: 0.45),
    glyph: _slate,
  );
  await _addBadge(
    style,
    '$_badgeIcon-visited',
    fill: _visitedColor,
    border: Colors.white,
    glyph: Colors.white,
  );
}

SymbolLayer peakMarkerLayer({
  required String id,
  required String sourceId,
  required List<Object> filter,
}) {
  return SymbolLayer(
    id: id,
    sourceId: sourceId,
    filter: filter,
    iconImageExpression: [
      'case',
      ['get', 'visited'],
      '$_badgeIcon-visited',
      _badgeIcon,
    ],
    iconAllowOverlap: true,
    iconIgnorePlacement: true,
    symbolSortKeyExpression: [
      '-',
      0,
      ['coalesce', ['get', 'ele'], 0],
    ],
    textFieldExpression: [
      'format',
      ['get', 'name'],
      <String, Object>{},
      '\n',
      <String, Object>{},
      [
        'case',
        ['has', 'ele'],
        [
          'concat',
          ['to-string', ['get', 'ele']],
          ' m',
        ],
        '',
      ],
      {'font-scale': 0.85},
    ],
    textFont: ['DIN Pro Medium', 'Arial Unicode MS Regular'],
    textSize: 12,
    textAnchor: TextAnchor.LEFT,
    textJustify: TextJustify.LEFT,
    textOffset: [1.1, 0],
    textOptional: true,
    textColor: _labelColor.toARGB32(),
    textHaloColor: Colors.white.toARGB32(),
    textHaloWidth: 1.5,
  );
}

Future<void> hideStylePeakLabels(StyleManager style) async {
  const layerId = 'natural-point-label';
  try {
    if (!await style.styleLayerExists(layerId)) return;
    final existing = await style.getStyleLayerProperty(layerId, 'filter');
    final notPeak = [
      'match',
      ['get', 'maki'],
      ['mountain', 'volcano'],
      false,
      true,
    ];
    final value = existing.value;
    await style.setStyleLayerProperty(
      layerId,
      'filter',
      value is List && value.isNotEmpty ? ['all', value, notPeak] : notPeak,
    );
  } catch (_) {}
}

Future<void> _addBadge(
  StyleManager style,
  String id, {
  required Color fill,
  required Color border,
  required Color glyph,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(_pixelRatio);
  _paintBadge(canvas, _badgeSize, fill: fill, border: border, glyph: glyph);
  final width = (_badgeSize.width * _pixelRatio).round();
  final height = (_badgeSize.height * _pixelRatio).round();
  final image = await recorder.endRecording().toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  if (bytes == null) return;
  await style.addStyleImage(
    id,
    _pixelRatio,
    MbxImage(width: width, height: height, data: bytes.buffer.asUint8List()),
    false,
    [],
    [],
    null,
  );
}

void _paintBadge(
  Canvas canvas,
  Size size, {
  required Color fill,
  required Color border,
  required Color glyph,
}) {
  final center = size.center(Offset.zero);
  final radius = size.width / 2 - 1.5;
  canvas.drawCircle(
    center.translate(0, 0.8),
    radius,
    Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
  );
  canvas.drawCircle(center, radius, Paint()..color = fill);
  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..color = border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5,
  );
  _paintGlyph(
    canvas,
    Rect.fromCenter(center: center.translate(0, -0.3), width: 12, height: 9),
    glyph,
  );
}

void _paintGlyph(Canvas canvas, Rect rect, Color color) {
  final big = Path()
    ..moveTo(rect.left + rect.width * 0.42, rect.top)
    ..lineTo(rect.left + rect.width * 0.84, rect.bottom)
    ..lineTo(rect.left, rect.bottom)
    ..close();
  final small = Path()
    ..moveTo(rect.left + rect.width * 0.72, rect.top + rect.height * 0.38)
    ..lineTo(rect.right, rect.bottom)
    ..lineTo(rect.left + rect.width * 0.5, rect.bottom)
    ..close();
  canvas.drawPath(small, Paint()..color = color.withValues(alpha: 0.75));
  canvas.drawPath(big, Paint()..color = color);
}
