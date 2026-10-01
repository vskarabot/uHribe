import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhribe/theme.dart';

/// Reads the text theme as a widget sees it. [ThemeData.textTheme] carries
/// only colors — the `Theme` widget merges the sizes in from the typography's
/// geometry — so the ramp can only be checked from inside a build.
Future<TextTheme> _resolveTextTheme(WidgetTester tester, ThemeData theme) async {
  late TextTheme resolved;
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Builder(
        builder: (context) {
          resolved = Theme.of(context).textTheme;
          return const SizedBox();
        },
      ),
    ),
  );
  // MaterialApp lerps between themes via AnimatedTheme, so a single pump
  // still reports the previous theme when this helper is called twice.
  await tester.pumpAndSettle();
  return resolved;
}

void main() {
  group('AppTheme', () {
    testWidgets('gives every style in the ramp a size, in both brightnesses',
        (tester) async {
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        final text = await _resolveTextTheme(tester, theme);
        expect(text.bodyLarge?.fontSize, isNotNull);
        expect(text.bodyMedium?.fontSize, isNotNull);
        expect(text.labelLarge?.fontSize, isNotNull);
        expect(text.titleMedium?.fontSize, isNotNull);
      }
    });

    testWidgets('scales the ramp down but keeps its proportions',
        (tester) async {
      final scaled = await _resolveTextTheme(tester, AppTheme.light);
      final base = await _resolveTextTheme(
        tester,
        ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2F6B4F)),
        ),
      );

      expect(scaled.bodyLarge!.fontSize, lessThan(base.bodyLarge!.fontSize!));
      expect(
        scaled.bodyLarge!.fontSize! / scaled.bodySmall!.fontSize!,
        closeTo(base.bodyLarge!.fontSize! / base.bodySmall!.fontSize!, 0.001),
      );
    });

    testWidgets('mutes icons rather than painting them at text strength',
        (tester) async {
      final theme = AppTheme.light;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Column(
              children: [
                const TextField(
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.search, size: 20),
                  ),
                ),
                ActionChip(
                  avatar: const Icon(Icons.filter_alt_outlined, size: 16),
                  label: const Text('filter'),
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Both icons resolve through different paths — InputDecorator reads
      // prefixIconColor, the chip reads ChipThemeData.iconTheme — so neither
      // inherits the global icon theme and both are worth pinning.
      for (final icon in [Icons.search, Icons.filter_alt_outlined]) {
        final resolved = IconTheme.of(tester.element(find.byIcon(icon))).color!;
        expect(resolved.a, lessThan(1.0), reason: '$icon should be muted');
        expect(resolved.toARGB32() & 0xFFFFFF,
            theme.colorScheme.onSurfaceVariant.toARGB32() & 0xFFFFFF);
      }
    });

    testWidgets('draws filter chips with the same hairline as a text field',
        (tester) async {
      final theme = AppTheme.light;
      final border = theme.inputDecorationTheme.enabledBorder as OutlineInputBorder;

      expect(theme.chipTheme.side!.color, border.borderSide.color);
      // Shared hairline, deliberately different silhouette: chips are fully
      // rounded, fields keep a soft-boxed corner.
      expect(theme.chipTheme.shape, isA<StadiumBorder>());
      expect(border.borderRadius, BorderRadius.circular(AppTheme.inputRadius));
      // The muted, lighter token — not the heavier `outline` this started on.
      expect(border.borderSide.color.toARGB32() & 0xFFFFFF,
          theme.colorScheme.outlineVariant.toARGB32() & 0xFFFFFF);
      expect(border.borderSide.color.a, lessThan(1.0));
    });

    test('gives bottom sheets a wide, light grip and one shared corner', () {
      final sheet = AppTheme.light.bottomSheetTheme;
      final colorScheme = AppTheme.light.colorScheme;

      // Wider and lighter than Material's 32x4 in onSurfaceVariant.
      expect(sheet.dragHandleSize!.width, greaterThan(32));
      expect(sheet.dragHandleColor, colorScheme.outlineVariant);
      expect(
        (sheet.shape as RoundedRectangleBorder).borderRadius,
        const BorderRadius.vertical(top: Radius.circular(AppTheme.sheetRadius)),
      );
    });
  });
}
