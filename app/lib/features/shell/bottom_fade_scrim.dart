import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Fades whatever is scrolling underneath into the bottom edge of the screen:
/// a blur that ramps from nothing at the top of the strip to a full frost at
/// the very bottom, with a matching wash of [ColorScheme.surface] over it.
///
/// Sits behind the floating nav bar and starts at the bar's midline, so list
/// items dissolve as they pass under it instead of being sliced off by it.
class BottomFadeScrim extends StatelessWidget {
  const BottomFadeScrim({super.key, required this.height});

  /// How far up from the bottom of the screen the fade reaches.
  final double height;

  /// The blur is built from stacked bands rather than one gradient-masked
  /// layer: a [BackdropFilter] inside a [ShaderMask] reads the save layer it
  /// was put in, not the page, so it comes out empty. Each band is clipped to
  /// start a little lower and blurs everything already painted below its top
  /// edge — including the bands before it — so the sigmas compound downwards
  /// and there is no single seam where the blur switches on.
  static const _bands = 5;
  static const _maxSigma = 14.0;

  /// Per-band sigma, chosen so the *cumulative* blur grows quadratically down
  /// the strip. Stacked gaussians add in quadrature, hence the roots: the top
  /// band is near-invisible (a hard blur edge up there would read as a line
  /// across the page) and the ramp only gets steep near the bottom.
  static double _bandSigma(int i) {
    double cumulative(int n) => _maxSigma * math.pow((n + 1) / _bands, 2).toDouble();
    final previous = i == 0 ? 0.0 : cumulative(i - 1);
    return math.sqrt(cumulative(i) * cumulative(i) - previous * previous);
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;

    return IgnorePointer(
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            for (var i = 0; i < _bands; i++)
              Positioned(
                top: height * i / _bands,
                left: 0,
                right: 0,
                bottom: 0,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(
                      sigmaX: _bandSigma(i),
                      sigmaY: _bandSigma(i),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            // Blur alone keeps the content's color, so a busy list still reads
            // as clutter down there however smeared it is. The wash is what
            // actually takes it to the page background by the bottom edge.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    surface.withValues(alpha: 0),
                    surface.withValues(alpha: 0.25),
                    surface.withValues(alpha: 0.85),
                  ],
                  stops: const [0, 0.55, 1],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
