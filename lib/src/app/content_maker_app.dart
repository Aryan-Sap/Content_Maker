import 'package:flutter/material.dart';

import '../presentation/onboarding/login_screen.dart';

class ContentMakerApp extends StatelessWidget {
  const ContentMakerApp({super.key});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF8AB4F8);
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
        ).copyWith(
          primary: accent,
          onPrimary: const Color(0xFF0B1220),
          primaryContainer: const Color(0xFF2A3A55),
          onPrimaryContainer: const Color(0xFFDCE7FA),
          secondary: const Color(0xFFA8B4C4),
          onSecondary: const Color(0xFF10151C),
          secondaryContainer: const Color(0xFF242B35),
          onSecondaryContainer: const Color(0xFFE4E9F0),
          tertiary: const Color(0xFFB8C4B8),
          onTertiary: const Color(0xFF101510),
          tertiaryContainer: const Color(0xFF232823),
          onTertiaryContainer: const Color(0xFFE4E9E4),
          surface: const Color(0xFF121417),
          onSurface: const Color(0xFFE6E8EB),
          onSurfaceVariant: const Color(0xFFAAB1BA),
          outline: const Color(0xFF3C4048),
          outlineVariant: const Color(0xFF2A2D33),
        );
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Content Maker',
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0B0D10),
        dividerColor: const Color(0xFF2B2E34),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0B0D10),
          surfaceTintColor: Colors.transparent,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF14171B),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFF2A2D33)),
          ),
        ),
        textTheme: ThemeData.dark().textTheme.apply(
          bodyColor: const Color(0xFFE2E4E8),
          displayColor: const Color(0xFFF2F4F6),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF171A1F),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF383C44)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF383C44)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: accent, width: 1.4),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(shape: buttonShape),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(shape: buttonShape),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(shape: buttonShape),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: ButtonStyle(
            shape: WidgetStatePropertyAll<OutlinedBorder>(buttonShape),
          ),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            shape: WidgetStatePropertyAll<OutlinedBorder>(buttonShape),
          ),
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          side: const BorderSide(color: Color(0xFF383C44)),
          backgroundColor: const Color(0xFF171A1F),
          selectedColor: const Color(0xFF2A3A55),
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: const Color(0xFF171A1F),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0xFF2A2D33)),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: const Color(0xFF14171B),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF232830),
          contentTextStyle: const TextStyle(color: Color(0xFFE6E8EB)),
          actionTextColor: accent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
            color: const Color(0xFF242830),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF3C4048)),
          ),
        ),
        scrollbarTheme: const ScrollbarThemeData(
          thumbColor: WidgetStatePropertyAll(Color(0xFF4A4F58)),
          trackColor: WidgetStatePropertyAll(Color(0xFF181B20)),
          radius: Radius.circular(4),
        ),
        sliderTheme: const SliderThemeData(
          activeTrackColor: accent,
          thumbColor: accent,
          overlayColor: Color(0x338AB4F8),
        ),
      ),
      home: const LoginScreen(),
    );
  }
}
