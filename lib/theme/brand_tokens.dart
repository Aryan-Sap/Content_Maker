import 'package:flutter/material.dart';
import 'studio_theme.dart';

/// Compatibility names for the single light studio palette.
/// New widgets consume StudioTheme.of(context); these aliases keep legacy
/// const widgets on the same authored palette during their migration.
abstract final class Brand {
  static const ink = StudioValues.neutral100; // text on solid accent
  static const inkDeep = StudioValues.neutral98;
  static const lime = StudioValues.green34;
  static const blue = Color(0xFF426181);
  static const blueSoft = StudioValues.green34;
  static const cream = StudioValues.neutral12;
  static const surface = StudioValues.neutral100;
  static const surfaceRaised = StudioValues.neutral100;
  static const surfaceSunken = StudioValues.neutral93;
  static const surfaceHover = StudioValues.green88;
  static const line = StudioValues.neutral84;
  static const lineStrong = Color(0xFF899486);
  static const muted = StudioValues.neutral42;
  static const faint = StudioValues.neutral42;
  static const success = StudioValues.green34;
  static const warning = Color(0xFF8A5A18);
  static const danger = StudioValues.red42;
  static const videoTrack = Color(0xFFDCE5ED);
  static const textTrack = Color(0xFFE9DFED);
  static const audioTrack = StudioValues.green88;
  static const textAccent = Color(0xFF77528A);
  static const mediaCanvas = Color(0xFF101418);
  static const onMedia = Color(0xFFFFFFFF);
  static const onMediaMuted = Color(0xCCFFFFFF);
  static const mediaBorder = Color(0x80FFFFFF);
  static const mediaOverlay = Color(0xCC000000);
  static const mediaShadow = Color(0x66000000);
  static const mediaLabel = Color(0x73000000);
  static const scrim = Color(0xAD1D2420);
  static const shadow = Color(0x10000000);
  static const displayFont = StudioTheme.displayFont;
  static const bodyFont = StudioTheme.bodyFont;
  static const radius = 8.0;
  static const radiusSmall = 6.0;
}
