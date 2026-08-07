import 'package:flutter/material.dart';

import '../application/app_session_store.dart';
import '../presentation/onboarding/first_run_tutorial_screen.dart';
import 'brand.dart';

class ContentMakerApp extends StatelessWidget {
  const ContentMakerApp({
    super.key,
    this.sessionStore = const AppSessionStore(),
  });

  final AppSessionStore sessionStore;

  @override
  Widget build(BuildContext context) {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: Brand.lime,
          brightness: Brightness.dark,
        ).copyWith(
          primary: Brand.lime,
          onPrimary: Brand.ink,
          primaryContainer: const Color(0xFF3A4413),
          onPrimaryContainer: const Color(0xFFE9FBAF),
          secondary: Brand.blue,
          onSecondary: Brand.cream,
          secondaryContainer: const Color(0xFF232D66),
          onSecondaryContainer: const Color(0xFFDFE4FF),
          tertiary: Brand.blueSoft,
          onTertiary: Brand.ink,
          tertiaryContainer: const Color(0xFF262B45),
          onTertiaryContainer: const Color(0xFFDFE4FF),
          surface: Brand.surface,
          onSurface: Brand.cream,
          onSurfaceVariant: Brand.muted,
          outline: Brand.lineStrong,
          outlineVariant: Brand.line,
          error: const Color(0xFFFF8A7A),
        );
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Brand.radiusSmall),
    );
    final displayStyle = const TextStyle(
      fontFamily: Brand.displayFont,
      fontWeight: FontWeight.w700,
      color: Brand.cream,
      height: 1.1,
    );
    final baseTextTheme = ThemeData.dark().textTheme.apply(
      fontFamily: Brand.bodyFont,
      bodyColor: const Color(0xFFEDEAE2),
      displayColor: Brand.cream,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Content Maker',
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        fontFamily: Brand.bodyFont,
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
          surfaceTintColor: Colors.transparent,
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
            backgroundColor: Brand.lime,
            foregroundColor: Brand.ink,
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
            foregroundColor: Brand.cream,
            side: const BorderSide(color: Brand.lineStrong),
            textStyle: const TextStyle(
              fontFamily: Brand.bodyFont,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            shape: buttonShape,
            foregroundColor: Brand.muted,
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: ButtonStyle(
            shape: WidgetStatePropertyAll<OutlinedBorder>(buttonShape),
          ),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            shape: WidgetStatePropertyAll<OutlinedBorder>(buttonShape),
            side: const WidgetStatePropertyAll(BorderSide(color: Brand.line)),
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? Brand.lime
                  : Brand.surfaceSunken,
            ),
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? Brand.ink
                  : Brand.muted,
            ),
            textStyle: const WidgetStatePropertyAll(
              TextStyle(
                fontFamily: Brand.bodyFont,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Brand.radiusSmall),
          ),
          side: const BorderSide(color: Brand.line),
          backgroundColor: Brand.surfaceSunken,
          selectedColor: Brand.lime,
          labelStyle: const TextStyle(color: Brand.cream),
          secondaryLabelStyle: const TextStyle(color: Brand.ink),
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
          thumbColor: WidgetStatePropertyAll(Color(0xFF55503F)),
          trackColor: WidgetStatePropertyAll(Brand.surfaceSunken),
          radius: Radius.circular(4),
        ),
        sliderTheme: const SliderThemeData(
          activeTrackColor: Brand.lime,
          thumbColor: Brand.lime,
          inactiveTrackColor: Brand.line,
          overlayColor: Color(0x33C9F63C),
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
      ),
      home: AppEntryGate(store: sessionStore),
    );
  }
}
