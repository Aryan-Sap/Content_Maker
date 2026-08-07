import 'timeline_clip.dart';

class ManualEditProject {
  const ManualEditProject({
    required this.outputPath,
    required this.width,
    required this.height,
    required this.frameRate,
    required this.backgroundHexColor,
    required this.blurredBackgroundEnabled,
    required this.clips,
  });

  final String outputPath;
  final int width;
  final int height;
  final int frameRate;
  final String backgroundHexColor;
  final bool blurredBackgroundEnabled;
  final List<TimelineClip> clips;

  factory ManualEditProject.fromJson(Object? json) {
    final map = _asMap(json);
    final clipsJson = map['clips'];
    return ManualEditProject(
      outputPath: _readString(map, 'outputPath') ?? '',
      width: _readInt(map, 'width', 1080),
      height: _readInt(map, 'height', 1920),
      frameRate: _readInt(map, 'frameRate', 60),
      backgroundHexColor: _readString(map, 'backgroundHexColor') ?? '101418',
      blurredBackgroundEnabled: _readBool(
        map,
        'blurredBackgroundEnabled',
        true,
      ),
      clips: clipsJson is List
          ? List.unmodifiable(clipsJson.map(TimelineClip.fromJson))
          : const [],
    );
  }

  double get durationSeconds {
    var end = 0.0;
    for (final clip in clips) {
      if (!clip.enabled) {
        continue;
      }
      if (clip.timelineEndSeconds > end) {
        end = clip.timelineEndSeconds;
      }
    }
    return end <= 0 ? 1 : end;
  }

  List<TimelineClip> get enabledVideoClips {
    return clips
        .where(
          (clip) => clip.isVideo && clip.enabled && clip.durationSeconds > 0,
        )
        .toList();
  }

  List<TimelineClip> get enabledTextClips {
    return clips
        .where(
          (clip) =>
              clip.isText &&
              clip.enabled &&
              clip.durationSeconds > 0 &&
              (clip.text?.content.trim().isNotEmpty ?? false),
        )
        .toList();
  }

  List<TimelineClip> get audibleAudioClips {
    return clips
        .where(
          (clip) =>
              clip.isAudio &&
              clip.enabled &&
              !clip.muted &&
              clip.volume > 0 &&
              clip.durationSeconds > 0,
        )
        .toList();
  }

  ManualEditProject copyWith({
    String? outputPath,
    int? width,
    int? height,
    int? frameRate,
    String? backgroundHexColor,
    bool? blurredBackgroundEnabled,
    List<TimelineClip>? clips,
  }) {
    return ManualEditProject(
      outputPath: outputPath ?? this.outputPath,
      width: width ?? this.width,
      height: height ?? this.height,
      frameRate: frameRate ?? this.frameRate,
      backgroundHexColor: backgroundHexColor ?? this.backgroundHexColor,
      blurredBackgroundEnabled:
          blurredBackgroundEnabled ?? this.blurredBackgroundEnabled,
      clips: clips ?? this.clips,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'schemaVersion': 1,
      'outputPath': outputPath,
      'width': width,
      'height': height,
      'frameRate': frameRate,
      'backgroundHexColor': backgroundHexColor,
      'blurredBackgroundEnabled': blurredBackgroundEnabled,
      'clips': [for (final clip in clips) clip.toJson()],
    };
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
