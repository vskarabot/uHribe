import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'liquid_glass_pill.dart';

class PillNavDestination {
  const PillNavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class PillNavBar extends StatelessWidget {
  const PillNavBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final List<PillNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  static const _height = 64.0;
  static const _bottomMargin = 12.0;
  static const _labelFontSize = 11.0;

  static const _inset = 8.0;

  static const _labelInset = 8.0;

  static const _minLabelScale = 0.82;

  static const horizontalMargin = 24.0;

  static double centerOffset(BuildContext context) =>
      math.max(MediaQuery.paddingOf(context).bottom, _bottomMargin) + _height / 2;

  double _labelScale(BuildContext context, double itemWidth) {
    final textScaler = MediaQuery.textScalerOf(context);
    var widest = 0.0;
    for (final destination in destinations) {
      final painter = TextPainter(
        text: TextSpan(text: destination.label, style: _labelStyle(selected: true)),
        textDirection: Directionality.of(context),
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      widest = math.max(widest, painter.width);
    }

    final room = itemWidth - _labelInset * 2;
    return widest <= room ? 1.0 : math.max(room / widest, _minLabelScale);
  }

  static TextStyle _labelStyle({required bool selected, double scale = 1}) => TextStyle(
        fontSize: _labelFontSize * scale,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      );

  @override
  Widget build(BuildContext context) {
    final isIOS = defaultTargetPlatform == TargetPlatform.iOS;
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(
        horizontalMargin,
        0,
        horizontalMargin,
        _bottomMargin,
      ),
      child: SizedBox(
        height: _height,
        child: LiquidGlassPill(
          borderRadius: 32,
          tint: colorScheme.surface,
          tintStrength: isIOS ? 0.12 : 0.16,
          blurSigma: 8,
          refraction: isIOS ? 7 : 16,
          animated: false,
          borderColor: colorScheme.outlineVariant.withValues(alpha: isIOS ? 0.45 : 0.55),
          borderWidth: 1,
          shadows: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.10),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
          child: Padding(
            padding: const EdgeInsets.all(_inset),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final itemWidth = constraints.maxWidth / destinations.length;
                final labelScale = _labelScale(context, itemWidth);
                return Stack(
                  children: [
                    _LiquidSelectionBlob(
                      index: selectedIndex,
                      itemWidth: itemWidth,
                      color: colorScheme.surface.withValues(alpha: 0.6),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < destinations.length; i++)
                          Expanded(
                            child: _PillNavItem(
                              destination: destinations[i],
                              selected: i == selectedIndex,
                              labelScale: labelScale,
                              onTap: () => onDestinationSelected(i),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _LiquidSelectionBlob extends StatefulWidget {
  const _LiquidSelectionBlob({
    required this.index,
    required this.itemWidth,
    required this.color,
  });

  final int index;
  final double itemWidth;
  final Color color;

  @override
  State<_LiquidSelectionBlob> createState() => _LiquidSelectionBlobState();
}

class _LiquidSelectionBlobState extends State<_LiquidSelectionBlob>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..value = 1;

  late double _from = widget.index.toDouble();
  late double _to = widget.index.toDouble();

  @override
  void didUpdateWidget(covariant _LiquidSelectionBlob oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index) {
      _from = _currentPosition;
      _to = widget.index.toDouble();
      _controller.forward(from: 0);
    }
  }

  double get _currentPosition {
    final t = Curves.easeOutBack.transform(_controller.value.clamp(0.0, 1.0));
    return _from + (_to - _from) * t;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final position = _currentPosition;
        final linearT = _controller.value.clamp(0.0, 1.0);
        final bulge = (_to - _from).abs() == 0 ? 0.0 : math.sin(math.pi * linearT);

        final baseWidth = widget.itemWidth;
        final extra = baseWidth * bulge * 0.3;

        return Positioned(
          left: position * widget.itemWidth - extra / 2,
          top: 0,
          bottom: 0,
          width: baseWidth + extra,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        );
      },
    );
  }
}

class _PillNavItem extends StatelessWidget {
  const _PillNavItem({
    required this.destination,
    required this.selected,
    required this.labelScale,
    required this.onTap,
  });

  final PillNavDestination destination;
  final bool selected;
  final double labelScale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = selected ? colorScheme.onSurface : colorScheme.onSurfaceVariant;

    final content = AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 150),
      style: PillNavBar._labelStyle(selected: selected, scale: labelScale)
          .copyWith(color: color),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(selected ? destination.selectedIcon : destination.icon, color: color, size: 24),
          const SizedBox(height: 3),
          Text(destination.label, maxLines: 1, softWrap: false, overflow: TextOverflow.fade),
        ],
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(child: content),
    );
  }
}
