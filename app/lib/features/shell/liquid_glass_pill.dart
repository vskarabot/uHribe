import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class LiquidGlassPill extends StatefulWidget {
  const LiquidGlassPill({
    super.key,
    required this.child,
    required this.borderRadius,
    required this.tint,
    this.tintStrength = 0.6,
    this.refraction = 12,
    this.animated = true,
    this.blurSigma = 18,
    this.borderColor,
    this.borderWidth = 1,
    this.shadows,
  });

  final Widget child;
  final double borderRadius;
  final Color tint;
  final double tintStrength;
  final double refraction;
  final bool animated;
  final double blurSigma;
  final Color? borderColor;
  final double borderWidth;

  final List<BoxShadow>? shadows;

  @override
  State<LiquidGlassPill> createState() => _LiquidGlassPillState();
}

class _LiquidGlassPillState extends State<LiquidGlassPill> with SingleTickerProviderStateMixin {
  static Future<ui.FragmentProgram>? _programFuture;

  ui.FragmentProgram? _program;
  Ticker? _ticker;
  double _time = 0;

  @override
  void initState() {
    super.initState();
    _programFuture ??= ui.FragmentProgram.fromAsset('shaders/liquid_glass.frag');
    _programFuture!.then((program) {
      if (!mounted) return;
      setState(() => _program = program);
    });
    if (widget.animated) {
      _ticker = createTicker((elapsed) {
        setState(() => _time = elapsed.inMilliseconds / 1000.0);
      })..start();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.borderColor;
    final shape = BorderRadius.circular(widget.borderRadius);

    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: shape, boxShadow: widget.shadows),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: shape,
          border: borderColor == null
              ? null
              : Border.all(color: borderColor, width: widget.borderWidth),
        ),
        child: ClipRRect(
          borderRadius: shape,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return BackdropFilter(
                filter: _buildFilter(constraints.biggest),
                child: widget.child,
              );
            },
          ),
        ),
      ),
    );
  }

  ui.ImageFilter _buildFilter(Size size) {
    final blur = ui.ImageFilter.blur(sigmaX: widget.blurSigma, sigmaY: widget.blurSigma);

    final program = _program;
    if (program == null || !ui.ImageFilter.isShaderFilterSupported) {
      return blur;
    }
    final shader = program.fragmentShader()
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, widget.borderRadius)
      ..setFloat(3, widget.refraction)
      ..setFloat(4, _time)
      ..setFloat(5, widget.animated ? 1.0 : 0.0)
      ..setFloat(6, widget.tint.r)
      ..setFloat(7, widget.tint.g)
      ..setFloat(8, widget.tint.b)
      ..setFloat(9, widget.tintStrength);
    return ui.ImageFilter.compose(outer: ui.ImageFilter.shader(shader), inner: blur);
  }
}
