import 'composition_spec.dart';
import 'export_settings.dart';

class RenderPreset {
  const RenderPreset({
    required this.id,
    required this.name,
    required this.composition,
    required this.exportSettings,
  });

  final String id;
  final String name;
  final ShortsCompositionSpec composition;
  final ExportSettings exportSettings;

  RenderPreset copyWith({
    String? id,
    String? name,
    ShortsCompositionSpec? composition,
    ExportSettings? exportSettings,
  }) {
    return RenderPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      composition: composition ?? this.composition,
      exportSettings: exportSettings ?? this.exportSettings,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'composition': composition.toJson(),
      'exportSettings': exportSettings.toJson(),
    };
  }

  factory RenderPreset.fromJson(Object? json) {
    final map = _asMap(json);
    return RenderPreset(
      id: _readString(map, 'id') ?? gameplayShort.id,
      name: _readString(map, 'name') ?? gameplayShort.name,
      composition: ShortsCompositionSpec.fromJson(map['composition']),
      exportSettings: ExportSettings.fromJson(map['exportSettings']),
    );
  }

  static const gameplayShort = RenderPreset(
    id: 'gameplay_short_v1',
    name: 'Gameplay Short',
    composition: ShortsCompositionSpec(
      width: 1080,
      height: 1920,
      foregroundHeight: 608,
      blurSigma: 34,
      blurSteps: 3,
      backgroundDarkness: 0.04,
      backgroundSaturation: 1.24,
      foregroundSaturation: 1.38,
      contrast: 1.18,
      gamma: 1.03,
      sharpness: 0.55,
      verticalOffset: 0.5,
    ),
    exportSettings: ExportSettings(
      frameRate: 60,
      crf: 16,
      videoCodec: 'libx264',
      encoderPreset: 'medium',
      audioBitrate: '192k',
      temporalSmoothing: TemporalSmoothingMode.fpsConversion,
      motionBlur: false,
      panningBlurIntensity: 0,
    ),
  );
}

Map<String, Object?> _asMap(Object? json) {
  if (json is Map<String, Object?>) {
    return json;
  }
  if (json is Map) {
    return json.map((key, value) => MapEntry('$key', value));
  }
  return const {};
}

String? _readString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) {
    return null;
  }
  final text = '$value';
  return text.isEmpty ? null : text;
}
