import 'package:flutter/material.dart';
import '../src/app/brand.dart';
import 'studio_theme.dart';

ThemeData buildEditorTheme() {
  final colorScheme = buildStudioTheme(Brightness.light).colorScheme;
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(Brand.radiusSmall),
  );
  final displayStyle = const TextStyle(
    fontFamily: Brand.displayFont,
    fontWeight: FontWeight.w700,
    color: Brand.cream,
    height: 1.1,
  );
  final baseTextTheme = ThemeData.light().textTheme.apply(
    fontFamily: Brand.bodyFont,
    bodyColor: Brand.cream,
    displayColor: Brand.cream,
  );

  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    extensions: const [StudioTheme.light],
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    fontFamily: Brand.bodyFont,
    visualDensity: VisualDensity.standard,
    scaffoldBackgroundColor: Brand.inkDeep,
    dividerColor: Brand.line,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.windows: BrandPageTransitionsBuilder(),
        TargetPlatform.macOS: BrandPageTransitionsBuilder(),
        TargetPlatform.linux: BrandPageTransitionsBuilder(),
        TargetPlatform.android: BrandPageTransitionsBuilder(),
        TargetPlatform.iOS: BrandPageTransitionsBuilder(),
      },
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Brand.inkDeep,
      elevation: 0,
      toolbarHeight: 64,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      shadowColor: Colors.transparent,
      shape: const Border(bottom: BorderSide(color: Brand.line)),
      centerTitle: false,
      titleTextStyle: displayStyle.copyWith(fontSize: 18),
    ),
    cardTheme: CardThemeData(
      color: Brand.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Brand.radius),
        side: const BorderSide(color: Brand.line),
      ),
    ),
    textTheme: baseTextTheme.copyWith(
      displayLarge: displayStyle.copyWith(fontSize: 56),
      displayMedium: displayStyle.copyWith(fontSize: 44),
      displaySmall: displayStyle.copyWith(fontSize: 36),
      headlineLarge: displayStyle.copyWith(fontSize: 30),
      headlineMedium: displayStyle.copyWith(fontSize: 26),
      headlineSmall: displayStyle.copyWith(fontSize: 22),
      titleLarge: displayStyle.copyWith(fontSize: 19),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Brand.surfaceSunken,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      hintStyle: const TextStyle(color: Brand.faint),
      labelStyle: const TextStyle(color: Brand.muted),
      prefixIconColor: Brand.muted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Brand.radiusSmall),
        borderSide: const BorderSide(color: Brand.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Brand.radiusSmall),
        borderSide: const BorderSide(color: Brand.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Brand.radiusSmall),
        borderSide: const BorderSide(color: Brand.lime, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: buttonShape,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        backgroundColor: Brand.lime,
        foregroundColor: Brand.ink,
        elevation: 0,
        overlayColor: Brand.ink.withValues(alpha: 0.08),
        textStyle: const TextStyle(
          fontFamily: Brand.bodyFont,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: buttonShape,
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        foregroundColor: Brand.cream,
        side: const BorderSide(color: Brand.lineStrong),
        overlayColor: Brand.lime.withValues(alpha: 0.08),
        textStyle: const TextStyle(
          fontFamily: Brand.bodyFont,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: buttonShape,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        foregroundColor: Brand.muted,
        overlayColor: Brand.lime.withValues(alpha: 0.08),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll<OutlinedBorder>(buttonShape),
        foregroundColor: const WidgetStatePropertyAll(Brand.muted),
        overlayColor: WidgetStatePropertyAll(
          Brand.lime.withValues(alpha: 0.08),
        ),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll<OutlinedBorder>(buttonShape),
        side: const WidgetStatePropertyAll(BorderSide(color: Brand.line)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Brand.surfaceHover
              : Brand.surfaceSunken,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? Brand.cream : Brand.muted,
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontFamily: Brand.bodyFont, fontWeight: FontWeight.w600),
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Brand.radiusSmall),
      ),
      side: const BorderSide(color: Brand.line),
      backgroundColor: Brand.surfaceSunken,
      selectedColor: Brand.surfaceHover,
      labelStyle: const TextStyle(
        color: Brand.cream,
        fontFamily: Brand.bodyFont,
      ),
      secondaryLabelStyle: const TextStyle(
        color: Brand.cream,
        fontFamily: Brand.bodyFont,
      ),
      iconTheme: const IconThemeData(color: Brand.muted, size: 18),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Brand.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Brand.line),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Brand.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Brand.radius),
        side: const BorderSide(color: Brand.line),
      ),
      titleTextStyle: displayStyle.copyWith(fontSize: 20),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Brand.surfaceRaised,
      contentTextStyle: const TextStyle(
        color: Brand.cream,
        fontFamily: Brand.bodyFont,
      ),
      actionTextColor: Brand.lime,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Brand.line),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: Brand.surfaceRaised,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Brand.lineStrong),
      ),
      textStyle: const TextStyle(color: Brand.cream, fontSize: 12),
    ),
    scrollbarTheme: const ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(Brand.lineStrong),
      trackColor: WidgetStatePropertyAll(Brand.surfaceSunken),
      radius: Radius.circular(4),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: Brand.lime,
      thumbColor: Brand.lime,
      inactiveTrackColor: Brand.line,
      overlayColor: Color(0x22386345),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? Brand.ink : Brand.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Brand.lime
            : Brand.surfaceSunken,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Brand.lime
            : Brand.lineStrong,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Brand.lime
            : Colors.transparent,
      ),
      checkColor: const WidgetStatePropertyAll(Brand.ink),
      side: const BorderSide(color: Brand.lineStrong, width: 1.4),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Brand.lime,
      linearTrackColor: Brand.surfaceSunken,
    ),
  );
}
