import 'package:flutter/material.dart';

/// Measured primitives; semantic roles below are the public widget API.
abstract final class StudioValues {
  static const neutral98 = Color(0xFFF7F7F2);
  static const neutral100 = Color(0xFFFFFFFF);
  static const neutral93 = Color(0xFFEDEEE7);
  static const neutral84 = Color(0xFFD5D8CF);
  static const neutral42 = Color(0xFF60675F);
  static const neutral12 = Color(0xFF1D2420);
  static const green34 = Color(0xFF386345);
  static const green88 = Color(0xFFDCE8D8);
  static const red42 = Color(0xFFAC382E);
  static const ms120 = Duration(milliseconds: 120);
  static const ms180 = Duration(milliseconds: 180);
  static const ms240 = Duration(milliseconds: 240);
}

@immutable
class StudioTheme extends ThemeExtension<StudioTheme> {
  const StudioTheme({
    required this.canvas,
    required this.panel,
    required this.inset,
    required this.ink,
    required this.muted,
    required this.line,
    required this.accent,
    required this.selection,
    required this.danger,
  });
  final Color canvas, panel, inset, ink, muted, line, accent, selection, danger;
  static const light = StudioTheme(
    canvas: StudioValues.neutral98,
    panel: StudioValues.neutral100,
    inset: StudioValues.neutral93,
    ink: StudioValues.neutral12,
    muted: StudioValues.neutral42,
    line: StudioValues.neutral84,
    accent: StudioValues.green34,
    selection: StudioValues.green88,
    danger: StudioValues.red42,
  );
  static const dark = StudioTheme(
    canvas: Color(0xFF141715),
    panel: Color(0xFF1B201D),
    inset: Color(0xFF242B26),
    ink: Color(0xFFF1F3EC),
    muted: Color(0xFFACB6AC),
    line: Color(0xFF3B463E),
    accent: Color(0xFFC0D8A7),
    selection: Color(0xFF35472F),
    danger: Color(0xFFFFABA2),
  );
  static StudioTheme of(BuildContext context) {
    final value = Theme.of(context).extension<StudioTheme>();
    assert(value != null, 'Use buildStudioTheme to install StudioTheme.');
    return value!;
  }

  static const panelRadius = BorderRadius.all(Radius.circular(8));
  static const controlRadius = BorderRadius.all(Radius.circular(6));
  static const bodyFont = 'Archivo';
  static const displayFont = 'Bricolage Grotesque';
  static const titleSize = 34.0;
  static const eyebrowSize = 11.0;
  static const compactBreakpoint = 600.0;
  static const compactPagePadding = 16.0;
  static const quick = StudioValues.ms180;
  static const reveal = StudioValues.ms240;
  static const loadingDelay = StudioValues.ms180;
  static const curve = Curves.easeOutCubic;
  static const undoDuration = Duration(seconds: 8);
  static const accessibleUndoDuration = Duration(seconds: 30);
  static Duration motion(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
  @override
  StudioTheme copyWith({
    Color? canvas,
    Color? panel,
    Color? inset,
    Color? ink,
    Color? muted,
    Color? line,
    Color? accent,
    Color? selection,
    Color? danger,
  }) => StudioTheme(
    canvas: canvas ?? this.canvas,
    panel: panel ?? this.panel,
    inset: inset ?? this.inset,
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    line: line ?? this.line,
    accent: accent ?? this.accent,
    selection: selection ?? this.selection,
    danger: danger ?? this.danger,
  );
  @override
  StudioTheme lerp(covariant StudioTheme? other, double t) {
    if (other == null) return this;
    return StudioTheme(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      inset: Color.lerp(inset, other.inset, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      line: Color.lerp(line, other.line, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      selection: Color.lerp(selection, other.selection, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

ThemeData buildStudioTheme(Brightness brightness) {
  final c = brightness == Brightness.light
      ? StudioTheme.light
      : StudioTheme.dark;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: c.panel,
    primaryContainer: c.selection,
    onPrimaryContainer: c.ink,
    secondary: c.accent,
    onSecondary: c.panel,
    secondaryContainer: c.selection,
    onSecondaryContainer: c.ink,
    surface: c.panel,
    onSurface: c.ink,
    onSurfaceVariant: c.muted,
    surfaceContainerHighest: c.inset,
    surfaceContainerHigh: c.inset,
    surfaceContainer: c.panel,
    surfaceContainerLow: c.canvas,
    surfaceContainerLowest: c.canvas,
    outline: c.line,
    outlineVariant: c.line,
    error: c.danger,
    onError: c.panel,
  );
  final shape = RoundedRectangleBorder(borderRadius: StudioTheme.controlRadius);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    extensions: [c],
    fontFamily: StudioTheme.bodyFont,
    scaffoldBackgroundColor: c.canvas,
    dividerColor: c.line,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    appBarTheme: AppBarTheme(
      backgroundColor: c.canvas,
      foregroundColor: c.ink,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    textTheme: ThemeData(brightness: brightness).textTheme.apply(
      fontFamily: StudioTheme.bodyFont,
      bodyColor: c.ink,
      displayColor: c.ink,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: shape,
        minimumSize: const Size(40, 44),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: shape,
        minimumSize: const Size(40, 44),
        foregroundColor: c.ink,
        side: BorderSide(color: c.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.panel,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: StudioTheme.controlRadius,
        borderSide: BorderSide(color: c.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: StudioTheme.controlRadius,
        borderSide: BorderSide(color: c.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: StudioTheme.controlRadius,
        borderSide: BorderSide(color: c.accent, width: 2),
      ),
    ),
  );
}
