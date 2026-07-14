import 'render_preset.dart';

class AutoEditPreset {
  const AutoEditPreset({
    required this.id,
    required this.name,
    required this.renderPreset,
    this.trimStartSeconds = 0,
    this.trimEndSeconds,
    this.sourceAudioVolume = 1,
    this.overlayAudioVolume = 0.75,
  });

  final String id;
  final String name;
  final RenderPreset renderPreset;
  final double trimStartSeconds;
  final double? trimEndSeconds;
  final double sourceAudioVolume;
  final double overlayAudioVolume;

  AutoEditPreset copyWith({
    String? id,
    String? name,
    RenderPreset? renderPreset,
    double? trimStartSeconds,
    double? trimEndSeconds,
    bool clearTrimEndSeconds = false,
    double? sourceAudioVolume,
    double? overlayAudioVolume,
  }) {
    return AutoEditPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      renderPreset: renderPreset ?? this.renderPreset,
      trimStartSeconds: trimStartSeconds ?? this.trimStartSeconds,
      trimEndSeconds: clearTrimEndSeconds
          ? null
          : (trimEndSeconds ?? this.trimEndSeconds),
      sourceAudioVolume: sourceAudioVolume ?? this.sourceAudioVolume,
      overlayAudioVolume: overlayAudioVolume ?? this.overlayAudioVolume,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'renderPreset': renderPreset.toJson(),
      'trimStartSeconds': trimStartSeconds,
      'trimEndSeconds': trimEndSeconds,
      'sourceAudioVolume': sourceAudioVolume,
      'overlayAudioVolume': overlayAudioVolume,
    };
  }

  factory AutoEditPreset.fromJson(Object? json) {
    final map = _asMap(json);
    return AutoEditPreset(
      id: _readString(map, 'id') ?? '',
      name: _readString(map, 'name') ?? 'Untitled preset',
      renderPreset: RenderPreset.fromJson(map['renderPreset']),
      trimStartSeconds: _readDouble(map, 'trimStartSeconds', 0),
      trimEndSeconds: _readNullableDouble(map, 'trimEndSeconds'),
      sourceAudioVolume: _readDouble(map, 'sourceAudioVolume', 1),
      overlayAudioVolume: _readDouble(map, 'overlayAudioVolume', 0.75),
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
  return _readNullableDouble(map, key) ?? fallback;
}

double? _readNullableDouble(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}
