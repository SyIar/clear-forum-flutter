import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/settings_store.dart';
import '../widgets/glass.dart';

ThemeData buildAppTheme(Brightness brightness, [SettingsStore? preferences]) {
  if (defaultTargetPlatform == TargetPlatform.android) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2467C9), brightness: brightness),
      scaffoldBackgroundColor: brightness == Brightness.dark ? const Color(0xFF101318) : const Color(0xFFF7F9FC),
      visualDensity: VisualDensity.standard,
      appBarTheme: const AppBarThemeData(centerTitle: false),
    );
  }
  final dark = brightness == Brightness.dark;
  final accent = Color(
    preferences?.getInt('customPrimaryColor', fallback: 0xFF007AFF) ??
        0xFF007AFF,
  );
  final font = preferences?.fontFamily ?? 'system';
  final family = switch (font) {
    'notoSans' => 'NotoSansCJKsc',
    _ => null,
  };
  final fallback = font == 'system' ? null : const ['NotoSansCJKsc'];
  final controlFamily =
      family ??
      Typography.material2021(platform: defaultTargetPlatform)
          .black
          .labelLarge
          ?.fontFamily;
  final (canvas, card) = dark
      ? switch (preferences?.getString(
          'darkPalette',
          fallback: 'amoled_dark',
        )) {
          'blue_dark' => (const Color(0xFF10151B), const Color(0xFF1D252E)),
          'grey_dark' => (const Color(0xFF171717), const Color(0xFF252525)),
          _ => (Colors.black, const Color(0xFF181818)),
        }
      : (Colors.white, const Color(0xFFF7F7F7));
  final foreground = dark ? const Color(0xFFF2F2F2) : const Color(0xFF171717);
  final secondaryText = dark
      ? const Color(0xFFAAAAAA)
      : const Color(0xFF666666);
  final line = dark ? const Color(0xFF353535) : const Color(0xFFE4E4E4);
  var colors = ColorScheme.fromSeed(seedColor: accent, brightness: brightness)
      .copyWith(
        primary: dark
            ? Color.lerp(accent, Colors.white, .28)!
            : Color.lerp(accent, Colors.black, .2)!,
        onPrimary: Colors.white,
        primaryContainer: dark
            ? const Color(0xFF07375E)
            : const Color(0xFFE6F2FC),
        onPrimaryContainer: dark
            ? const Color(0xFFC4E5FF)
            : const Color(0xFF135F94),
        secondary: secondaryText,
        secondaryContainer: dark
            ? const Color(0xFF282828)
            : const Color(0xFFF0F0F0),
        onSecondaryContainer: foreground,
        tertiary: secondaryText,
        surface: canvas,
        onSurface: foreground,
        onSurfaceVariant: secondaryText,
        surfaceContainerLowest: canvas,
        surfaceContainerLow: card,
        surfaceContainer: dark
            ? const Color(0xFF202020)
            : const Color(0xFFF3F3F3),
        surfaceContainerHigh: dark
            ? const Color(0xFF292929)
            : const Color(0xFFEEEEEE),
        surfaceContainerHighest: dark
            ? const Color(0xFF333333)
            : const Color(0xFFE9E9E9),
        outline: secondaryText,
        outlineVariant: line,
        surfaceTint: Colors.transparent,
      );
  final background =
      preferences?.getString('themeBackground').isNotEmpty == true;
  if (background) {
    final opacity =
        preferences
            ?.getDouble('themeSurfaceOpacity', fallback: .9)
            .clamp(.2, 1.0) ??
        .9;
    colors = colors.copyWith(
      surfaceContainerLow: card.withValues(alpha: opacity),
    );
  }
  final radius = (preferences?.getDouble('radius', fallback: 22) ?? 22).clamp(
    0.0,
    32.0,
  );
  final outline = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(24),
    side: BorderSide(color: line, width: .7),
  );
  ButtonStyle controls({bool prominent = false}) => ButtonStyle(
    backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? secondaryText.withValues(alpha: .5)
          : prominent || states.contains(WidgetState.selected)
          ? colors.primary
          : foreground,
    ),
    side: const WidgetStatePropertyAll(BorderSide.none),
    elevation: const WidgetStatePropertyAll(0),
    shape: const WidgetStatePropertyAll(StadiumBorder()),
    minimumSize: const WidgetStatePropertyAll(Size(44, 40)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    ),
    textStyle: WidgetStatePropertyAll(
      TextStyle(
        fontFamily: controlFamily,
        fontFamilyFallback: fallback,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    ),
    backgroundBuilder: glassButtonBackground,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colors,
    fontFamily: family,
    fontFamilyFallback: fallback,
    canvasColor: canvas,
    scaffoldBackgroundColor: background ? Colors.transparent : canvas,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: preferences?.getBool('toolbarPrimaryColor') == true
          ? colors.primaryContainer
          : background
          ? Colors.transparent
          : canvas,
      foregroundColor: preferences?.getBool('toolbarPrimaryColor') == true
          ? colors.onPrimaryContainer
          : foreground,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
    ),
    cardTheme: CardThemeData(
      color: colors.surfaceContainerLow,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: line.withValues(alpha: .6), width: .5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(style: controls(prominent: true)),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: controls(prominent: true),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(style: controls()),
    textButtonTheme: TextButtonThemeData(style: controls()),
    iconButtonTheme: IconButtonThemeData(
      style: controls().copyWith(
        padding: const WidgetStatePropertyAll(EdgeInsets.all(10)),
        minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide(color: colors.primary),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 62,
      elevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      indicatorColor: colors.primaryContainer,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: controlFamily,
          fontFamilyFallback: fallback,
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w400,
          color: states.contains(WidgetState.selected)
              ? colors.primary
              : secondaryText,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 23,
          color: states.contains(WidgetState.selected)
              ? colors.primary
              : secondaryText,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: colors.surfaceContainerLow,
      selectedColor: colors.primaryContainer,
      side: BorderSide(color: line, width: .7),
      shape: const StadiumBorder(),
      labelStyle: TextStyle(
        fontFamily: controlFamily,
        fontFamilyFallback: fallback,
        fontSize: 13,
        color: foreground,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 5),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: card,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: Colors.black26,
      shape: outline,
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(card),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(outline),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      shape: outline,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      shape: outline,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    dividerTheme: DividerThemeData(color: line, space: 1, thickness: .5),
  );
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 16, height: 1.4),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        fontSize: 14,
        height: 1.4,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
