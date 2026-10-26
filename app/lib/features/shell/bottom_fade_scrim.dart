import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class BottomFadeScrim extends StatelessWidget {
  const BottomFadeScrim({super.key, required this.height});

  final double height;

  static const _bands = 5;
  static const _maxSigma = 14.0;

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
