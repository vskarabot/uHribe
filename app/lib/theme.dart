import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const fontFamily = 'Manrope';

  static const inputRadius = 28.0;

  static const panelRadius = 20.0;

  static const sheetRadius = 24.0;

  static const _textScale = 0.88;

  static BorderSide fieldBorder(ColorScheme colorScheme) =>
      BorderSide(color: colorScheme.outline.withValues(alpha: 0.5));

  static BorderSide _chipBorder(ColorScheme colorScheme) =>
      BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.7));

  static Color _iconColor(ColorScheme colorScheme) =>
      colorScheme.onSurfaceVariant.withValues(alpha: 0.7);

  static const _seed = Color(0xFF2F6B4F);

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.light,
    );
    return _base(colorScheme);
  }

  static ThemeData get dark {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    );
    return _base(colorScheme);
  }

  static ThemeData _base(ColorScheme colorScheme) {
    final typography = Typography.material2021(
      platform: defaultTargetPlatform,
      colorScheme: colorScheme,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: fontFamily,
      typography: typography.copyWith(
        englishLike: _scaled(typography.englishLike),
        dense: _scaled(typography.dense),
        tall: _scaled(typography.tall),
      ),
      scaffoldBackgroundColor: colorScheme.surface,
      iconTheme: IconThemeData(size: 20, color: _iconColor(colorScheme)),
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: colorScheme.onSurface,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerLowest,
        iconColor: _iconColor(colorScheme),
        prefixIconColor: _iconColor(colorScheme),
        suffixIconColor: _iconColor(colorScheme),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: fieldBorder(colorScheme),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: fieldBorder(colorScheme),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w600),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(panelRadius),
          side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.5)),
        ),
      ),
      chipTheme: ChipThemeData(
        labelStyle: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w500,
          color: WidgetStateColor.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? colorScheme.onSecondaryContainer
                : colorScheme.onSurfaceVariant;
          }),
        ),
        backgroundColor: colorScheme.surfaceContainerLow,
        selectedColor: colorScheme.secondaryContainer,
        checkmarkColor: colorScheme.onSecondaryContainer,
        iconTheme: IconThemeData(size: 16, color: _iconColor(colorScheme)),
        side: _chipBorder(colorScheme),
        shape: const StadiumBorder(),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        dragHandleSize: const Size(56, 5),
        dragHandleColor: colorScheme.outlineVariant,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(sheetRadius)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontFamily: fontFamily, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  static TextTheme _scaled(TextTheme ramp) {
    TextStyle? scale(TextStyle? style) {
      final size = style?.fontSize;
      if (style == null || size == null) return style;
      return style.copyWith(fontSize: size * _textScale);
    }

    return TextTheme(
      displayLarge: scale(ramp.displayLarge),
      displayMedium: scale(ramp.displayMedium),
      displaySmall: scale(ramp.displaySmall),
      headlineLarge: scale(ramp.headlineLarge),
      headlineMedium: scale(ramp.headlineMedium),
      headlineSmall: scale(ramp.headlineSmall),
      titleLarge: scale(ramp.titleLarge),
      titleMedium: scale(ramp.titleMedium),
      titleSmall: scale(ramp.titleSmall),
      bodyLarge: scale(ramp.bodyLarge),
      bodyMedium: scale(ramp.bodyMedium),
      bodySmall: scale(ramp.bodySmall),
      labelLarge: scale(ramp.labelLarge),
      labelMedium: scale(ramp.labelMedium),
      labelSmall: scale(ramp.labelSmall),
    );
  }
}

class ShadowedField extends StatelessWidget {
  const ShadowedField({super.key, required this.child, this.radius = AppTheme.inputRadius});

  final Widget child;

  final double radius;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.04),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: child,
    );
  }
}
