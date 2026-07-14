enum TemporalSmoothingMode { fpsConversion, motionInterpolation }

/// Speed/quality trade-off for FFmpeg `minterpolate` motion interpolation.
///
/// `fast` uses hexagon-based search with a small search window and simple
/// overlapped block compensation — several times faster than `quality`.
/// `balanced` keeps the default EPZS estimator with a reduced search window.
/// `quality` matches the original slow-but-smooth configuration.
enum InterpolationQuality { fast, balanced, quality }

extension InterpolationQualityDetails on InterpolationQuality {
  String get label {
    return switch (this) {
      InterpolationQuality.fast => 'Fast',
      InterpolationQuality.balanced => 'Balanced',
      InterpolationQuality.quality => 'Quality',
    };
  }

  /// The minterpolate option string (without the leading filter name).
  String minterpolateOptions(int frameRate) {
    return switch (this) {
      InterpolationQuality.fast =>
        'fps=$frameRate:mi_mode=mci:mc_mode=obmc:me_mode=bidir'
            ':me=hexbs:search_param=16:scd=fdiff',
      InterpolationQuality.balanced =>
        'fps=$frameRate:mi_mode=mci:mc_mode=obmc:me_mode=bidir'
            ':search_param=24:scd=fdiff',
      InterpolationQuality.quality =>
        'fps=$frameRate:mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1',
    };
  }
}

class ExportSettings {
  const ExportSettings({
    required this.frameRate,
    required this.crf,
    required this.videoCodec,
    required this.encoderPreset,
    required this.audioBitrate,
    required this.temporalSmoothing,
    required this.motionBlur,
    required this.panningBlurIntensity,
    this.interpolationQuality = InterpolationQuality.balanced,
  });

  final int frameRate;
  final int crf;
  final String videoCodec;
  final String encoderPreset;
  final String audioBitrate;
  final TemporalSmoothingMode temporalSmoothing;
  final bool motionBlur;
  final double panningBlurIntensity;
  final InterpolationQuality interpolationQuality;

  ExportSettings copyWith({
    int? frameRate,
    int? crf,
    String? videoCodec,
    String? encoderPreset,
    String? audioBitrate,
    TemporalSmoothingMode? temporalSmoothing,
    bool? motionBlur,
    double? panningBlurIntensity,
    InterpolationQuality? interpolationQuality,
  }) {
    return ExportSettings(
      frameRate: frameRate ?? this.frameRate,
      crf: crf ?? this.crf,
      videoCodec: videoCodec ?? this.videoCodec,
      encoderPreset: encoderPreset ?? this.encoderPreset,
      audioBitrate: audioBitrate ?? this.audioBitrate,
      temporalSmoothing: temporalSmoothing ?? this.temporalSmoothing,
      motionBlur: motionBlur ?? this.motionBlur,
      panningBlurIntensity: panningBlurIntensity ?? this.panningBlurIntensity,
      interpolationQuality: interpolationQuality ?? this.interpolationQuality,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'frameRate': frameRate,
      'crf': crf,
      'videoCodec': videoCodec,
      'encoderPreset': encoderPreset,
      'audioBitrate': audioBitrate,
      'temporalSmoothing': temporalSmoothing.name,
      'motionBlur': motionBlur,
      'panningBlurIntensity': panningBlurIntensity,
      'interpolationQuality': interpolationQuality.name,
    };
  }

  factory ExportSettings.fromJson(Object? json) {
    final map = _asMap(json);
    return ExportSettings(
      frameRate: _readInt(map, 'frameRate', 60),
      crf: _readInt(map, 'crf', 16),
      videoCodec: _readString(map, 'videoCodec') ?? 'libx264',
      encoderPreset: _readString(map, 'encoderPreset') ?? 'medium',
      audioBitrate: _readString(map, 'audioBitrate') ?? '192k',
      temporalSmoothing: _readEnum(
        TemporalSmoothingMode.values,
        _readString(map, 'temporalSmoothing'),
        TemporalSmoothingMode.fpsConversion,
      ),
      motionBlur: _readBool(map, 'motionBlur', false),
      panningBlurIntensity: _readDouble(map, 'panningBlurIntensity', 0),
      interpolationQuality: _readEnum(
        InterpolationQuality.values,
        _readString(map, 'interpolationQuality'),
        InterpolationQuality.balanced,
      ),
    );
  }
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

double _readDouble(Map<String, Object?> map, String key, double fallback) {
  final value = map[key];
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value) ?? fallback;
  }
  return fallback;
}

int _readInt(Map<String, Object?> map, String key, int fallback) {
  final value = map[key];
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? fallback;
  }
  return fallback;
}

bool _readBool(Map<String, Object?> map, String key, bool fallback) {
  final value = map[key];
  if (value is bool) {
    return value;
  }
  if (value is String) {
    return value.toLowerCase() == 'true';
  }
  return fallback;
}

T _readEnum<T extends Enum>(List<T> values, String? name, T fallback) {
  if (name == null) {
    return fallback;
  }
  for (final value in values) {
    if (value.name == name) {
      return value;
    }
  }
  return fallback;
}
