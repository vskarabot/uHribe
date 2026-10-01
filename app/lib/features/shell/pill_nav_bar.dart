import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'liquid_glass_pill.dart';

/// A single destination shown in a [PillNavBar].
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

/// A floating, pill-shaped bottom navigation bar in the style of iOS 26's
/// "Apple News+" tab bar, rendered with a real liquid-glass backdrop filter
/// (see [LiquidGlassPill]) rather than a flat blur-and-tint approximation.
///
/// iOS gets a subtler, static version of the effect (lighter refraction, no
/// shimmer) since that matches how the system's own floating bars behave
/// there. Android has no native equivalent of this material, so it gets the
/// full effect — stronger refraction and an animated sheen — to properly
/// replicate the look.
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

  /// The glass border the tabs sit inside, on all four sides.
  ///
  /// The tab strip is inset by this much and then split evenly, so a selected
  /// tab's blob can fill its whole share of the bar — running right up to
  /// where its neighbour begins — without ever touching the bar's own rim.
  static const _inset = 8.0;

  /// How far inside the blob a label has to stay.
  static const _labelInset = 8.0;

  /// Floor on the label scale: past this the type is too small to read, and
  /// crowded tabs are better solved with shorter labels than with 8pt text.
  static const _minLabelScale = 0.82;

  /// The gutter the bar keeps on either side.
  ///
  /// Public because anything that floats directly above the bar — the map's
  /// locate button — has to share the same edge, and two controls stacked in
  /// one column drifting apart by a few pixels is exactly the kind of
  /// misalignment that reads as sloppy without being obvious.
  static const horizontalMargin = 24.0;

  /// Distance from the bottom of the screen to the bar's vertical midline.
  ///
  /// The scrim behind the bar starts there, and it has to be measured against
  /// the same safe-area inset the bar itself sits on — so the number lives
  /// here, next to the padding that produces it, rather than being guessed at
  /// by the caller.
  static double centerOffset(BuildContext context) =>
      math.max(MediaQuery.paddingOf(context).bottom, _bottomMargin) + _height / 2;

  /// How far the labels have to shrink to fit the width a tab actually gets.
  ///
  /// One scale for all of them, measured off the widest label at its selected
  /// (bold) weight: scaling each label against its own tab would leave the
  /// bar in mismatched type, and letting the longest one wrap or clip is what
  /// made the selection look like it had text hanging out of it.
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
          // Barely tinted and heavily blurred: the bar is meant to be a piece
          // of frosted glass you can see the page through, so it earns its
          // presence from the blur, the rim and the shadow rather than from
          // being a solid panel parked over the content.
          tint: colorScheme.surface,
          // Low enough that the blurred page is what you actually see. Every
          // point of tint here is page you stop seeing, so it buys legibility
          // and nothing else.
          tintStrength: isIOS ? 0.12 : 0.16,
          blurSigma: 8,
          refraction: isIOS ? 7 : 16,
          animated: !isIOS,
          // A pale glass lip, not an outline: the halo below separates the
          // bar from the page, so this only has to trace its edge.
          borderColor: colorScheme.outlineVariant.withValues(alpha: isIOS ? 0.45 : 0.55),
          borderWidth: 1,
          // A faint halo rather than a drop: no offset, so it rings the pill
          // evenly instead of pooling under it and darkening the page below.
          shadows: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.10),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
          // One inset for the whole strip, rather than each tab keeping its
          // own margin: inside it a tab owns its full share of the width, so
          // the blob runs from one neighbour to the next instead of leaving a
          // gap on either side of every label.
          child: Padding(
            padding: const EdgeInsets.all(_inset),
            // The blob needs the per-item width up front: a LayoutBuilder
            // between the Stack and its Positioned child would break
            // parent-data resolution, so measure out here instead.
            child: LayoutBuilder(
              builder: (context, constraints) {
                final itemWidth = constraints.maxWidth / destinations.length;
                final labelScale = _labelScale(context, itemWidth);
                return Stack(
                  children: [
                    _LiquidSelectionBlob(
                      index: selectedIndex,
                      itemWidth: itemWidth,
                      // The bar's own tint, left see-through: selection reads
                      // as that one item being frosted a little heavier than
                      // the rest of the glass, not as a white chip parked on
                      // it. Enough fill to mark the tab, still thin enough
                      // that the blurred page carries through it.
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

/// The sliding highlight behind the selected destination — an oval that
/// travels to the newly selected item and briefly stretches along the way,
/// like a drop of liquid, instead of just snapping or fading in place.
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

        // The tab's full share of the strip, edge to edge: the bar's own
        // inset is what keeps the blob off the rim, so it needs no margin of
        // its own and nothing is left over between one tab and the next.
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
    // Selected sits on the blob's translucent fill, so it goes to full
    // onSurface strength while the rest stay a step back.
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
          // One line: a wrapped label would push the icon off centre and read
          // as two tabs' worth of text. The bar scales the type down instead
          // when the tabs get tight.
          Text(destination.label, maxLines: 1, softWrap: false, overflow: TextOverflow.fade),
        ],
      ),
    );

    // No ink splash: the sliding selection blob is the tap feedback, and a
    // ripple on top of it reads as the background changing twice.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(child: content),
    );
  }
}
