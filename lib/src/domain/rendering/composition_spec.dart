class ShortsCompositionSpec {
  const ShortsCompositionSpec({
    required this.width,
    required this.height,
    required this.foregroundHeight,
    required this.blurSigma,
    required this.blurSteps,
    required this.backgroundDarkness,
    required this.backgroundSaturation,
    required this.foregroundSaturation,
    required this.contrast,
    required this.gamma,
    required this.sharpness,
    required this.verticalOffset,
  });

  final int width;
  final int height;
  final int foregroundHeight;
  final double blurSigma;
  final int blurSteps;
  final double backgroundDarkness;
  final double backgroundSaturation;
  final double foregroundSaturation;
  final double contrast;
  final double gamma;
  final double sharpness;
  final double verticalOffset;

  int get foregroundY => ((height - foregroundHeight) * verticalOffset).round();

  ShortsCompositionSpec copyWith({
    int? width,
    int? height,
    int? foregroundHeight,
    double? blurSigma,
    int? blurSteps,
    double? backgroundDarkness,
    double? backgroundSaturation,
    double? foregroundSaturation,
    double? contrast,
    double? gamma,
    double? sharpness,
    double? verticalOffset,
  }) {
    return ShortsCompositionSpec(
      width: width ?? this.width,
      height: height ?? this.height,
      foregroundHeight: foregroundHeight ?? this.foregroundHeight,
      blurSigma: blurSigma ?? this.blurSigma,
      blurSteps: blurSteps ?? this.blurSteps,
      backgroundDarkness: backgroundDarkness ?? this.backgroundDarkness,
      backgroundSaturation: backgroundSaturation ?? this.backgroundSaturation,
      foregroundSaturation: foregroundSaturation ?? this.foregroundSaturation,
      contrast: contrast ?? this.contrast,
      gamma: gamma ?? this.gamma,
      sharpness: sharpness ?? this.sharpness,
      verticalOffset: verticalOffset ?? this.verticalOffset,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'width': width,
      'height': height,
      'foregroundHeight': foregroundHeight,
      'blurSigma': blurSigma,
      'blurSteps': blurSteps,
      'backgroundDarkness': backgroundDarkness,
      'backgroundSaturation': backgroundSaturation,
      'foregroundSaturation': foregroundSaturation,
      'contrast': contrast,
      'gamma': gamma,
      'sharpness': sharpness,
      'verticalOffset': verticalOffset,
    };
  }

  factory ShortsCompositionSpec.fromJson(Object? json) {
    final map = _asMap(json);
    return ShortsCompositionSpec(
      width: _readInt(map, 'width', 1080),
      height: _readInt(map, 'height', 1920),
      foregroundHeight: _readInt(map, 'foregroundHeight', 608),
      blurSigma: _readDouble(map, 'blurSigma', 34),
      blurSteps: _readInt(map, 'blurSteps', 3),
      backgroundDarkness: _readDouble(map, 'backgroundDarkness', 0.04),
      backgroundSaturation: _readDouble(map, 'backgroundSaturation', 1.24),
      foregroundSaturation: _readDouble(map, 'foregroundSaturation', 1.38),
      contrast: _readDouble(map, 'contrast', 1.18),
      gamma: _readDouble(map, 'gamma', 1.03),
      sharpness: _readDouble(map, 'sharpness', 0.55),
      verticalOffset: _readDouble(map, 'verticalOffset', 0.5),
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
