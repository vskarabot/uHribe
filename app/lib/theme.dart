import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// uHribe theme: Manrope font, an earthy green/stone palette that fits
/// mountains, and Material 3 components.
class AppTheme {
  AppTheme._();

  static const fontFamily = 'Manrope';

  /// Corner radius shared by text fields and the shadow [ShadowedField]
  /// casts behind them, so the two can't drift apart.
  ///
  /// Large enough to fully round a single-line field — the radius clamps to
  /// half the height, so this is a stadium in practice. Everything else you
  /// tap in this app is already a pill (the nav bar, its selection blob, the
  /// filter chips, the offline badge); a 16px-radius field sitting among them
  /// was the one control that looked like it came from somewhere else.
  static const inputRadius = 28.0;

  /// Corner radius for panels that hold content rather than take input —
  /// cards, the map's search results. Deliberately a step boxier than the
  /// controls: a surface that reads as pressable is a surface people press.
  static const panelRadius = 20.0;

  /// Top corner radius shared by every modal bottom sheet.
  static const sheetRadius = 24.0;

  /// Material's default type ramp reads large on a dense list of peaks, so
  /// the whole ramp is scaled down by this.
  static const _textScale = 0.88;

  /// The hairline drawn around text fields and filter chips alike, so the two
  /// can't drift into looking like different kinds of control.
  static BorderSide _fieldBorder(ColorScheme colorScheme) =>
      BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.7));

  /// Icons sit a step back from body text rather than matching its weight.
  static Color _iconColor(ColorScheme colorScheme) =>
      colorScheme.onSurfaceVariant.withValues(alpha: 0.7);

  // Deep forest green as the seed — reads as "mountains/outdoors" without
  // being a literal khaki/brown cliché.
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
    // The type ramp has to be scaled here, in the typography's *geometry*,
    // not in `textTheme`: ThemeData.textTheme carries only colors, and the
    // `Theme` widget merges the sizes in later from `geometryThemeFor` — so a
    // scaled textTheme would both start out null-sized and lose to that merge.
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
      // Material's 24px default is heavy next to the scaled-down type.
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
        // Opaque on purpose: a translucent fill would let the shadow
        // [ShadowedField] casts show through the middle of the field.
        fillColor: colorScheme.surfaceContainerLowest,
        iconColor: _iconColor(colorScheme),
        prefixIconColor: _iconColor(colorScheme),
        suffixIconColor: _iconColor(colorScheme),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: _fieldBorder(colorScheme),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: _fieldBorder(colorScheme),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      // Buttons are stadiums like every other control, rather than the boxy
      // 12px they used to carry — a rounded rectangle next to a pill nav bar
      // and stadium chips is what made the shapes look unrelated.
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
          // Lighter than the w600 these used to carry: a filter is a control,
          // not a heading, and semi-bold made it shout over the list itself.
          fontWeight: FontWeight.w500,
          color: WidgetStateColor.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? colorScheme.onSecondaryContainer
                : colorScheme.onSurfaceVariant;
          }),
        ),
        // Tinted, not the pure white the fields use. White chips read as
        // floating blobs against the surface's faint green cast — a field
        // gets away with it because its shadow explains why it's lifted.
        backgroundColor: colorScheme.surfaceContainerLow,
        selectedColor: colorScheme.secondaryContainer,
        checkmarkColor: colorScheme.onSecondaryContainer,
        iconTheme: IconThemeData(size: 16, color: _iconColor(colorScheme)),
        // Same hairline as a text field, so the filters stay part of the
        // search block — but fully rounded rather than boxy, which is what
        // separates a control you toggle from a field you type into.
        side: _fieldBorder(colorScheme),
        shape: const StadiumBorder(),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        // Material's elevation tint would drift the sheet's white away from
        // the page's, which is the opposite of reading as the same surface.
        surfaceTintColor: Colors.transparent,
        // Wider and lighter than Material's 32x4 in onSurfaceVariant: the
        // handle is a grip, and at the default it reads as a dark dash.
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

  /// The type ramp at [_textScale].
  ///
  /// Done by hand rather than with `TextTheme.apply(fontSizeFactor:)`, which
  /// asserts the moment any style in the ramp carries a null `fontSize` — and
  /// styles merged in from a theme's color-only typography do exactly that.
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

/// Lifts a text field off the page with a soft shadow.
///
/// A wrapper rather than part of [AppTheme]: `InputDecorationTheme` styles the
/// border and fill but has no shadow of its own, and `InputDecorator` clips to
/// its own bounds, so the shadow has to be cast from outside the field.
class ShadowedField extends StatelessWidget {
  const ShadowedField({super.key, required this.child, this.radius = AppTheme.inputRadius});

  final Widget child;

  /// The child's own corner radius. The shadow is drawn as a rounded rect
  /// behind the child, so anything but a field — the map's results panel,
  /// which is boxier — has to say so or its halo pokes out at the corners.
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
