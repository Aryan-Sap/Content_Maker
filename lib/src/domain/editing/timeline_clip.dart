import 'package:path/path.dart' as p;

enum TimelineClipType { video, audio, text, image }

enum TimelineTransition {
  cut,
  dissolve,
  fadeThroughBlack,
  slideLeft,
  slideRight,
  slideUp,
  slideDown,
  wipeLeft,
  wipeRight,
  wipeUp,
  wipeDown,
  zoomIn,
  zoomOut,
  circleOpen,
  circleClose,
  whipPan,
}

enum ClipAnimationType {
  none,
  kenBurnsIn,
  kenBurnsOut,
  zoomPunch,
  slideIn,
  popIn,
  fadeIn,
  fadeOut,
}

enum TextAnimationType { none, fade, slide, pop, typewriter }

enum ClipBlendMode { normal, screen, multiply, overlay, add, lighten, darken }

enum VoiceEffect { none, pitchUp, pitchDown, echo, reverb }

class ClipTransform {
  const ClipTransform({
    this.x = 0,
    this.y = 0,
    this.scale = 1,
    this.opacity = 1,
  });

  final double x;
  final double y;
  final double scale;
  final double opacity;

  bool get isDefault {
    const tolerance = 0.001;
    return x.abs() <= tolerance &&
        y.abs() <= tolerance &&
        (scale - 1).abs() <= tolerance &&
        (opacity - 1).abs() <= tolerance;
  }

  ClipTransform copyWith({
    double? x,
    double? y,
    double? scale,
    double? opacity,
  }) {
    return ClipTransform(
      x: x ?? this.x,
      y: y ?? this.y,
      scale: scale ?? this.scale,
      opacity: opacity ?? this.opacity,
    );
  }

  Map<String, Object?> toJson() {
    return {'x': x, 'y': y, 'scale': scale, 'opacity': opacity};
  }

  factory ClipTransform.fromJson(Object? json) {
    final map = _asMap(json);
    return ClipTransform(
      x: _readDouble(map, 'x', 0),
      y: _readDouble(map, 'y', 0),
      scale: _readDouble(map, 'scale', 1),
      opacity: _readDouble(map, 'opacity', 1),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ClipTransform &&
        other.x == x &&
        other.y == y &&
        other.scale == scale &&
        other.opacity == opacity;
  }

  @override
  int get hashCode => Object.hash(x, y, scale, opacity);
}

class ColorGrade {
  const ColorGrade({
    this.saturation = 1,
    this.brightness = 0,
    this.contrast = 1,
    this.gamma = 1,
    this.temperature = 0,
    this.tint = 0,
    this.highlights = 0,
    this.shadows = 0,
    this.fade = 0,
    this.vignette = 0,
    this.lutId,
    this.lutIntensity = 1,
  });

  final double saturation;
  final double brightness;
  final double contrast;
  final double gamma;
  final double temperature;
  final double tint;
  final double highlights;
  final double shadows;
  final double fade;
  final double vignette;
  final String? lutId;
  final double lutIntensity;

  bool get isDefault {
    const tolerance = 0.001;
    return (saturation - 1).abs() <= tolerance &&
        brightness.abs() <= tolerance &&
        (contrast - 1).abs() <= tolerance &&
        (gamma - 1).abs() <= tolerance &&
        temperature.abs() <= tolerance &&
        tint.abs() <= tolerance &&
        highlights.abs() <= tolerance &&
        shadows.abs() <= tolerance &&
        fade.abs() <= tolerance &&
        vignette.abs() <= tolerance &&
        (lutId == null || lutId!.isEmpty) &&
        (lutIntensity - 1).abs() <= tolerance;
  }

  ColorGrade copyWith({
    double? saturation,
    double? brightness,
    double? contrast,
    double? gamma,
    double? temperature,
    double? tint,
    double? highlights,
    double? shadows,
    double? fade,
    double? vignette,
    String? lutId,
    bool clearLutId = false,
    double? lutIntensity,
  }) {
    return ColorGrade(
      saturation: saturation ?? this.saturation,
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      gamma: gamma ?? this.gamma,
      temperature: temperature ?? this.temperature,
      tint: tint ?? this.tint,
      highlights: highlights ?? this.highlights,
      shadows: shadows ?? this.shadows,
      fade: fade ?? this.fade,
      vignette: vignette ?? this.vignette,
      lutId: clearLutId ? null : (lutId ?? this.lutId),
      lutIntensity: lutIntensity ?? this.lutIntensity,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'saturation': saturation,
      'brightness': brightness,
      'contrast': contrast,
      'gamma': gamma,
      'temperature': temperature,
      'tint': tint,
      'highlights': highlights,
      'shadows': shadows,
      'fade': fade,
      'vignette': vignette,
      'lutId': lutId,
      'lutIntensity': lutIntensity,
    };
  }

  factory ColorGrade.fromJson(Object? json) {
    final map = _asMap(json);
    return ColorGrade(
      saturation: _readDouble(map, 'saturation', 1),
      brightness: _readDouble(map, 'brightness', 0),
      contrast: _readDouble(map, 'contrast', 1),
      gamma: _readDouble(map, 'gamma', 1),
      temperature: _readDouble(map, 'temperature', 0),
      tint: _readDouble(map, 'tint', 0),
      highlights: _readDouble(map, 'highlights', 0),
      shadows: _readDouble(map, 'shadows', 0),
      fade: _readDouble(map, 'fade', 0),
      vignette: _readDouble(map, 'vignette', 0),
      lutId: _readString(map, 'lutId'),
      lutIntensity: _readDouble(map, 'lutIntensity', 1),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ColorGrade &&
        other.saturation == saturation &&
        other.brightness == brightness &&
        other.contrast == contrast &&
        other.gamma == gamma &&
        other.temperature == temperature &&
        other.tint == tint &&
        other.highlights == highlights &&
        other.shadows == shadows &&
        other.fade == fade &&
        other.vignette == vignette &&
        other.lutId == lutId &&
        other.lutIntensity == lutIntensity;
  }

  @override
  int get hashCode => Object.hash(
    saturation,
    brightness,
    contrast,
    gamma,
    temperature,
    tint,
    highlights,
    shadows,
    fade,
    vignette,
    lutId,
    lutIntensity,
  );
}

class ClipMotion {
  const ClipMotion({
    this.motionBlur = false,
    this.motionInterpolation = false,
    this.panningBlurIntensity = 0,
    this.speed = 1,
    this.reverse = false,
  });

  final bool motionBlur;
  final bool motionInterpolation;
  final double panningBlurIntensity;
  final double speed;
  final bool reverse;

  bool get isDefault {
    const tolerance = 0.001;
    return !motionBlur &&
        !motionInterpolation &&
        panningBlurIntensity.abs() <= tolerance &&
        (speed - 1).abs() <= tolerance &&
        !reverse;
  }

  ClipMotion copyWith({
    bool? motionBlur,
    bool? motionInterpolation,
    double? panningBlurIntensity,
    double? speed,
    bool? reverse,
  }) {
    return ClipMotion(
      motionBlur: motionBlur ?? this.motionBlur,
      motionInterpolation: motionInterpolation ?? this.motionInterpolation,
      panningBlurIntensity: panningBlurIntensity ?? this.panningBlurIntensity,
      speed: speed ?? this.speed,
      reverse: reverse ?? this.reverse,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'motionBlur': motionBlur,
      'motionInterpolation': motionInterpolation,
      'panningBlurIntensity': panningBlurIntensity,
      'speed': speed,
      'reverse': reverse,
    };
  }

  factory ClipMotion.fromJson(Object? json) {
    final map = _asMap(json);
    return ClipMotion(
      motionBlur: _readBool(map, 'motionBlur', false),
      motionInterpolation: _readBool(map, 'motionInterpolation', false),
      panningBlurIntensity: _readDouble(map, 'panningBlurIntensity', 0),
      speed: _readDouble(map, 'speed', 1),
      reverse: _readBool(map, 'reverse', false),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ClipMotion &&
        other.motionBlur == motionBlur &&
        other.motionInterpolation == motionInterpolation &&
        other.panningBlurIntensity == panningBlurIntensity &&
        other.speed == speed &&
        other.reverse == reverse;
  }

  @override
  int get hashCode => Object.hash(
    motionBlur,
    motionInterpolation,
    panningBlurIntensity,
    speed,
    reverse,
  );
}

class ChromaKeySpec {
  const ChromaKeySpec({
    this.enabled = false,
    this.colorHex = '00FF00',
    this.similarity = 0.18,
    this.blend = 0.08,
    this.despill = 0,
  });

  final bool enabled;
  final String colorHex;
  final double similarity;
  final double blend;
  final double despill;

  bool get isDefault => !enabled;

  ChromaKeySpec copyWith({
    bool? enabled,
    String? colorHex,
    double? similarity,
    double? blend,
    double? despill,
  }) {
    return ChromaKeySpec(
      enabled: enabled ?? this.enabled,
      colorHex: colorHex ?? this.colorHex,
      similarity: similarity ?? this.similarity,
      blend: blend ?? this.blend,
      despill: despill ?? this.despill,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'enabled': enabled,
      'colorHex': colorHex,
      'similarity': similarity,
      'blend': blend,
      'despill': despill,
    };
  }

  factory ChromaKeySpec.fromJson(Object? json) {
    final map = _asMap(json);
    return ChromaKeySpec(
      enabled: _readBool(map, 'enabled', false),
      colorHex: _readString(map, 'colorHex') ?? '00FF00',
      similarity: _readDouble(map, 'similarity', 0.18),
      blend: _readDouble(map, 'blend', 0.08),
      despill: _readDouble(map, 'despill', 0),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ChromaKeySpec &&
        other.enabled == enabled &&
        other.colorHex == colorHex &&
        other.similarity == similarity &&
        other.blend == blend &&
        other.despill == despill;
  }

  @override
  int get hashCode =>
      Object.hash(enabled, colorHex, similarity, blend, despill);
}

class ClipEffects {
  const ClipEffects({
    this.sharpness = 0,
    this.blendMode = ClipBlendMode.normal,
    this.chromaKey = const ChromaKeySpec(),
    this.overlayEffectId,
  });

  final double sharpness;
  final ClipBlendMode blendMode;
  final ChromaKeySpec chromaKey;
  final String? overlayEffectId;

  bool get isDefault {
    const tolerance = 0.001;
    return sharpness.abs() <= tolerance &&
        blendMode == ClipBlendMode.normal &&
        chromaKey.isDefault &&
        (overlayEffectId == null || overlayEffectId!.isEmpty);
  }

  ClipEffects copyWith({
    double? sharpness,
    ClipBlendMode? blendMode,
    ChromaKeySpec? chromaKey,
    String? overlayEffectId,
    bool clearOverlayEffectId = false,
  }) {
    return ClipEffects(
      sharpness: sharpness ?? this.sharpness,
      blendMode: blendMode ?? this.blendMode,
      chromaKey: chromaKey ?? this.chromaKey,
      overlayEffectId: clearOverlayEffectId
          ? null
          : (overlayEffectId ?? this.overlayEffectId),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'sharpness': sharpness,
      'blendMode': blendMode.name,
      'chromaKey': chromaKey.toJson(),
      'overlayEffectId': overlayEffectId,
    };
  }

  factory ClipEffects.fromJson(Object? json) {
    final map = _asMap(json);
    return ClipEffects(
      sharpness: _readDouble(map, 'sharpness', 0),
      blendMode: _readEnum(
        ClipBlendMode.values,
        _readString(map, 'blendMode'),
        ClipBlendMode.normal,
      ),
      chromaKey: ChromaKeySpec.fromJson(map['chromaKey']),
      overlayEffectId: _readString(map, 'overlayEffectId'),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ClipEffects &&
        other.sharpness == sharpness &&
        other.blendMode == blendMode &&
        other.chromaKey == chromaKey &&
        other.overlayEffectId == overlayEffectId;
  }

  @override
  int get hashCode =>
      Object.hash(sharpness, blendMode, chromaKey, overlayEffectId);
}

class ClipAnimation {
  const ClipAnimation({
    this.type = ClipAnimationType.none,
    this.inDurationSeconds = 0.35,
    this.outDurationSeconds = 0.35,
  });

  final ClipAnimationType type;
  final double inDurationSeconds;
  final double outDurationSeconds;

  bool get isDefault => type == ClipAnimationType.none;

  ClipAnimation copyWith({
    ClipAnimationType? type,
    double? inDurationSeconds,
    double? outDurationSeconds,
  }) {
    return ClipAnimation(
      type: type ?? this.type,
      inDurationSeconds: inDurationSeconds ?? this.inDurationSeconds,
      outDurationSeconds: outDurationSeconds ?? this.outDurationSeconds,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'type': type.name,
      'inDurationSeconds': inDurationSeconds,
      'outDurationSeconds': outDurationSeconds,
    };
  }

  factory ClipAnimation.fromJson(Object? json) {
    final map = _asMap(json);
    return ClipAnimation(
      type: _readEnum(
        ClipAnimationType.values,
        _readString(map, 'type'),
        ClipAnimationType.none,
      ),
      inDurationSeconds: _readDouble(map, 'inDurationSeconds', 0.35),
      outDurationSeconds: _readDouble(map, 'outDurationSeconds', 0.35),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ClipAnimation &&
        other.type == type &&
        other.inDurationSeconds == inDurationSeconds &&
        other.outDurationSeconds == outDurationSeconds;
  }

  @override
  int get hashCode => Object.hash(type, inDurationSeconds, outDurationSeconds);
}

class ClipAudio {
  const ClipAudio({
    this.fadeInSeconds = 0,
    this.fadeOutSeconds = 0,
    this.denoise = false,
    this.voiceEffect = VoiceEffect.none,
  });

  final double fadeInSeconds;
  final double fadeOutSeconds;
  final bool denoise;
  final VoiceEffect voiceEffect;

  bool get isDefault {
    const tolerance = 0.001;
    return fadeInSeconds.abs() <= tolerance &&
        fadeOutSeconds.abs() <= tolerance &&
        !denoise &&
        voiceEffect == VoiceEffect.none;
  }

  ClipAudio copyWith({
    double? fadeInSeconds,
    double? fadeOutSeconds,
    bool? denoise,
    VoiceEffect? voiceEffect,
  }) {
    return ClipAudio(
      fadeInSeconds: fadeInSeconds ?? this.fadeInSeconds,
      fadeOutSeconds: fadeOutSeconds ?? this.fadeOutSeconds,
      denoise: denoise ?? this.denoise,
      voiceEffect: voiceEffect ?? this.voiceEffect,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'fadeInSeconds': fadeInSeconds,
      'fadeOutSeconds': fadeOutSeconds,
      'denoise': denoise,
      'voiceEffect': voiceEffect.name,
    };
  }

  factory ClipAudio.fromJson(Object? json) {
    final map = _asMap(json);
    return ClipAudio(
      fadeInSeconds: _readDouble(map, 'fadeInSeconds', 0),
      fadeOutSeconds: _readDouble(map, 'fadeOutSeconds', 0),
      denoise: _readBool(map, 'denoise', false),
      voiceEffect: _readEnum(
        VoiceEffect.values,
        _readString(map, 'voiceEffect'),
        VoiceEffect.none,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ClipAudio &&
        other.fadeInSeconds == fadeInSeconds &&
        other.fadeOutSeconds == fadeOutSeconds &&
        other.denoise == denoise &&
        other.voiceEffect == voiceEffect;
  }

  @override
  int get hashCode =>
      Object.hash(fadeInSeconds, fadeOutSeconds, denoise, voiceEffect);
}

class TextSpec {
  const TextSpec({
    this.content = '',
    this.font = 'Arial',
    this.size = 64,
    this.colorHex = 'FFFFFF',
    this.strokeColorHex = '000000',
    this.strokeWidth = 0,
    this.shadow = false,
    this.box = false,
    this.align = 'center',
    this.x = 0,
    this.y = 0,
    this.animIn = TextAnimationType.none,
    this.animOut = TextAnimationType.none,
  });

  final String content;
  final String font;
  final double size;
  final String colorHex;
  final String strokeColorHex;
  final double strokeWidth;
  final bool shadow;
  final bool box;
  final String align;
  final double x;
  final double y;
  final TextAnimationType animIn;
  final TextAnimationType animOut;

  TextSpec copyWith({
    String? content,
    String? font,
    double? size,
    String? colorHex,
    String? strokeColorHex,
    double? strokeWidth,
    bool? shadow,
    bool? box,
    String? align,
    double? x,
    double? y,
    TextAnimationType? animIn,
    TextAnimationType? animOut,
  }) {
    return TextSpec(
      content: content ?? this.content,
      font: font ?? this.font,
      size: size ?? this.size,
      colorHex: colorHex ?? this.colorHex,
      strokeColorHex: strokeColorHex ?? this.strokeColorHex,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      shadow: shadow ?? this.shadow,
      box: box ?? this.box,
      align: align ?? this.align,
      x: x ?? this.x,
      y: y ?? this.y,
      animIn: animIn ?? this.animIn,
      animOut: animOut ?? this.animOut,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'content': content,
      'font': font,
      'size': size,
      'colorHex': colorHex,
      'strokeColorHex': strokeColorHex,
      'strokeWidth': strokeWidth,
      'shadow': shadow,
      'box': box,
      'align': align,
      'x': x,
      'y': y,
      'animIn': animIn.name,
      'animOut': animOut.name,
    };
  }

  factory TextSpec.fromJson(Object? json) {
    final map = _asMap(json);
    return TextSpec(
      content: _readString(map, 'content') ?? '',
      font: _readString(map, 'font') ?? 'Arial',
      size: _readDouble(map, 'size', 64),
      colorHex: _readString(map, 'colorHex') ?? 'FFFFFF',
      strokeColorHex: _readString(map, 'strokeColorHex') ?? '000000',
      strokeWidth: _readDouble(map, 'strokeWidth', 0),
      shadow: _readBool(map, 'shadow', false),
      box: _readBool(map, 'box', false),
      align: _readString(map, 'align') ?? 'center',
      x: _readDouble(map, 'x', 0),
      y: _readDouble(map, 'y', 0),
      animIn: _readEnum(
        TextAnimationType.values,
        _readString(map, 'animIn'),
        TextAnimationType.none,
      ),
      animOut: _readEnum(
        TextAnimationType.values,
        _readString(map, 'animOut'),
        TextAnimationType.none,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TextSpec &&
        other.content == content &&
        other.font == font &&
        other.size == size &&
        other.colorHex == colorHex &&
        other.strokeColorHex == strokeColorHex &&
        other.strokeWidth == strokeWidth &&
        other.shadow == shadow &&
        other.box == box &&
        other.align == align &&
        other.x == x &&
        other.y == y &&
        other.animIn == animIn &&
        other.animOut == animOut;
  }

  @override
  int get hashCode => Object.hash(
    content,
    font,
    size,
    colorHex,
    strokeColorHex,
    strokeWidth,
    shadow,
    box,
    align,
    x,
    y,
    animIn,
    animOut,
  );
}

class Keyframe<T extends Object> {
  const Keyframe({required this.seconds, required this.value});

  final double seconds;
  final T value;

  Map<String, Object?> toJson(Object? Function(T value) encodeValue) {
    return {'seconds': seconds, 'value': encodeValue(value)};
  }

  static Keyframe<T> fromJson<T extends Object>(
    Object? json,
    T Function(Object? value) decodeValue,
  ) {
    final map = _asMap(json);
    return Keyframe<T>(
      seconds: _readDouble(map, 'seconds', 0),
      value: decodeValue(map['value']),
    );
  }
}

class TimelineClip {
  static const defaultVideoDurationSeconds = 8.0;
  static const defaultAudioDurationSeconds = 12.0;

  TimelineClip({
    required this.id,
    required this.type,
    required this.path,
    required this.name,
    required this.trackIndex,
    required this.timelineStartSeconds,
    required this.trimStartSeconds,
    required this.trimEndSeconds,
    required this.volume,
    required this.enabled,
    required this.muted,
    required this.locked,
    required this.transition,
    required this.transitionDurationSeconds,
    required this.hasAudio,
    this.sourceFrameRate = 30,
    this.sourceDurationSeconds,
    this.thumbnailPath,
    ClipTransform? transform,
    ColorGrade? colorGrade,
    ClipMotion? motion,
    ClipEffects? effects,
    ClipAnimation? animation,
    ClipAudio? audio,
    this.text,
    double x = 0,
    double y = 0,
    double scale = 1,
    double opacity = 1,
    double saturation = 1,
    double brightness = 0,
    double contrast = 1,
    double gamma = 1,
    double temperature = 0,
    double tint = 0,
    double highlights = 0,
    double shadows = 0,
    double fade = 0,
    double vignette = 0,
    String? lutId,
    double lutIntensity = 1,
    double sharpness = 0,
    bool motionBlur = false,
    bool motionInterpolation = false,
    double panningBlurIntensity = 0,
    double speed = 1,
    bool reverse = false,
    double audioFadeInSeconds = 0,
    double audioFadeOutSeconds = 0,
    bool denoise = false,
    VoiceEffect voiceEffect = VoiceEffect.none,
  }) : transform =
           transform ??
           ClipTransform(x: x, y: y, scale: scale, opacity: opacity),
       colorGrade =
           colorGrade ??
           ColorGrade(
             saturation: saturation,
             brightness: brightness,
             contrast: contrast,
             gamma: gamma,
             temperature: temperature,
             tint: tint,
             highlights: highlights,
             shadows: shadows,
             fade: fade,
             vignette: vignette,
             lutId: lutId,
             lutIntensity: lutIntensity,
           ),
       motion =
           motion ??
           ClipMotion(
             motionBlur: motionBlur,
             motionInterpolation: motionInterpolation,
             panningBlurIntensity: panningBlurIntensity,
             speed: speed,
             reverse: reverse,
           ),
       effects = effects ?? ClipEffects(sharpness: sharpness),
       animation = animation ?? const ClipAnimation(),
       audio =
           audio ??
           ClipAudio(
             fadeInSeconds: audioFadeInSeconds,
             fadeOutSeconds: audioFadeOutSeconds,
             denoise: denoise,
             voiceEffect: voiceEffect,
           );

  factory TimelineClip.fromPath({
    required String id,
    required TimelineClipType type,
    required String path,
    required double timelineStartSeconds,
    double durationSeconds = 8,
    int trackIndex = 0,
    double sourceFrameRate = 30,
    double? sourceDurationSeconds,
    bool? hasAudio,
  }) {
    return TimelineClip(
      id: id,
      type: type,
      path: path,
      name: p.basename(path),
      trackIndex: trackIndex,
      timelineStartSeconds: timelineStartSeconds,
      trimStartSeconds: 0,
      trimEndSeconds: durationSeconds,
      volume: 1,
      enabled: true,
      muted: false,
      locked: false,
      transition: TimelineTransition.cut,
      transitionDurationSeconds: 0.35,
      hasAudio: hasAudio ?? type == TimelineClipType.audio,
      sourceFrameRate: sourceFrameRate,
      sourceDurationSeconds: sourceDurationSeconds,
    );
  }

  factory TimelineClip.fromJson(Object? json) {
    final map = _asMap(json);
    final type = _readEnum(
      TimelineClipType.values,
      _readString(map, 'type'),
      TimelineClipType.video,
    );
    return TimelineClip(
      id: _readString(map, 'id') ?? '',
      type: type,
      path: _readString(map, 'path') ?? '',
      name:
          _readString(map, 'name') ??
          p.basename(_readString(map, 'path') ?? ''),
      trackIndex: _readInt(map, 'trackIndex', 0),
      timelineStartSeconds: _readDouble(map, 'timelineStartSeconds', 0),
      trimStartSeconds: _readDouble(map, 'trimStartSeconds', 0),
      trimEndSeconds: _readDouble(
        map,
        'trimEndSeconds',
        type == TimelineClipType.audio
            ? defaultAudioDurationSeconds
            : defaultVideoDurationSeconds,
      ),
      volume: _readDouble(map, 'volume', 1),
      enabled: _readBool(map, 'enabled', true),
      muted: _readBool(map, 'muted', false),
      locked: _readBool(map, 'locked', false),
      transition: _readEnum(
        TimelineTransition.values,
        _readString(map, 'transition'),
        TimelineTransition.cut,
      ),
      transitionDurationSeconds: _readDouble(
        map,
        'transitionDurationSeconds',
        0.35,
      ),
      hasAudio: _readBool(map, 'hasAudio', type == TimelineClipType.audio),
      sourceFrameRate: _readDouble(map, 'sourceFrameRate', 30),
      sourceDurationSeconds: _readNullableDouble(map, 'sourceDurationSeconds'),
      thumbnailPath: _readString(map, 'thumbnailPath'),
      transform: map.containsKey('transform')
          ? ClipTransform.fromJson(map['transform'])
          : ClipTransform(
              x: _readDouble(map, 'x', 0),
              y: _readDouble(map, 'y', 0),
              scale: _readDouble(map, 'scale', 1),
              opacity: _readDouble(map, 'opacity', 1),
            ),
      colorGrade: map.containsKey('colorGrade')
          ? ColorGrade.fromJson(map['colorGrade'])
          : ColorGrade(
              saturation: _readDouble(map, 'saturation', 1),
              brightness: _readDouble(map, 'brightness', 0),
              contrast: _readDouble(map, 'contrast', 1),
              gamma: _readDouble(map, 'gamma', 1),
              temperature: _readDouble(map, 'temperature', 0),
              tint: _readDouble(map, 'tint', 0),
              highlights: _readDouble(map, 'highlights', 0),
              shadows: _readDouble(map, 'shadows', 0),
              fade: _readDouble(map, 'fade', 0),
              vignette: _readDouble(map, 'vignette', 0),
              lutId: _readString(map, 'lutId'),
              lutIntensity: _readDouble(map, 'lutIntensity', 1),
            ),
      motion: map.containsKey('motion')
          ? ClipMotion.fromJson(map['motion'])
          : ClipMotion(
              motionBlur: _readBool(map, 'motionBlur', false),
              motionInterpolation: _readBool(map, 'motionInterpolation', false),
              panningBlurIntensity: _readDouble(map, 'panningBlurIntensity', 0),
              speed: _readDouble(map, 'speed', 1),
              reverse: _readBool(map, 'reverse', false),
            ),
      effects: map.containsKey('effects')
          ? ClipEffects.fromJson(map['effects'])
          : ClipEffects(sharpness: _readDouble(map, 'sharpness', 0)),
      animation: ClipAnimation.fromJson(map['animation']),
      audio: map.containsKey('audio')
          ? ClipAudio.fromJson(map['audio'])
          : ClipAudio(
              fadeInSeconds: _readDouble(map, 'audioFadeInSeconds', 0),
              fadeOutSeconds: _readDouble(map, 'audioFadeOutSeconds', 0),
              denoise: _readBool(map, 'denoise', false),
              voiceEffect: _readEnum(
                VoiceEffect.values,
                _readString(map, 'voiceEffect'),
                VoiceEffect.none,
              ),
            ),
      text: map['text'] == null ? null : TextSpec.fromJson(map['text']),
    );
  }

  final String id;
  final TimelineClipType type;
  final String path;
  final String name;
  final int trackIndex;
  final double timelineStartSeconds;
  final double trimStartSeconds;
  final double trimEndSeconds;
  final double volume;
  final bool enabled;
  final bool muted;
  final bool locked;
  final TimelineTransition transition;
  final double transitionDurationSeconds;
  final bool hasAudio;
  final double sourceFrameRate;
  final double? sourceDurationSeconds;
  final String? thumbnailPath;
  final ClipTransform transform;
  final ColorGrade colorGrade;
  final ClipMotion motion;
  final ClipEffects effects;
  final ClipAnimation animation;
  final ClipAudio audio;
  final TextSpec? text;

  bool get isVideo => type == TimelineClipType.video;

  bool get isAudio => type == TimelineClipType.audio;

  bool get isText => type == TimelineClipType.text;

  bool get isImage => type == TimelineClipType.image;

  double get x => transform.x;

  double get y => transform.y;

  double get scale => transform.scale;

  double get opacity => transform.opacity;

  double get saturation => colorGrade.saturation;

  double get brightness => colorGrade.brightness;

  double get contrast => colorGrade.contrast;

  double get gamma => colorGrade.gamma;

  double get temperature => colorGrade.temperature;

  double get tint => colorGrade.tint;

  double get highlights => colorGrade.highlights;

  double get shadows => colorGrade.shadows;

  double get fade => colorGrade.fade;

  double get vignette => colorGrade.vignette;

  String? get lutId => colorGrade.lutId;

  double get lutIntensity => colorGrade.lutIntensity;

  double get sharpness => effects.sharpness;

  bool get motionBlur => motion.motionBlur;

  bool get motionInterpolation => motion.motionInterpolation;

  double get panningBlurIntensity => motion.panningBlurIntensity;

  double get speed => motion.speed;

  bool get reverse => motion.reverse;

  double get audioFadeInSeconds => audio.fadeInSeconds;

  double get audioFadeOutSeconds => audio.fadeOutSeconds;

  double get sourceTrimDurationSeconds {
    final duration = trimEndSeconds - trimStartSeconds;
    return duration <= 0 ? 0 : duration;
  }

  double get durationSeconds {
    final speedValue = speed <= 0 ? 1 : speed;
    final duration = sourceTrimDurationSeconds / speedValue;
    return duration <= 0 ? 0 : duration;
  }

  double get timelineEndSeconds => timelineStartSeconds + durationSeconds;

  bool isActiveAt(double seconds) {
    return enabled &&
        seconds >= timelineStartSeconds &&
        seconds <= timelineEndSeconds;
  }

  TimelineClip copyWith({
    String? id,
    TimelineClipType? type,
    String? path,
    String? name,
    int? trackIndex,
    double? timelineStartSeconds,
    double? trimStartSeconds,
    double? trimEndSeconds,
    double? x,
    double? y,
    double? scale,
    double? opacity,
    double? volume,
    bool? enabled,
    bool? muted,
    bool? locked,
    double? saturation,
    double? brightness,
    double? contrast,
    double? gamma,
    double? temperature,
    double? tint,
    double? highlights,
    double? shadows,
    double? fade,
    double? vignette,
    String? lutId,
    bool clearLutId = false,
    double? lutIntensity,
    double? sharpness,
    bool? motionBlur,
    bool? motionInterpolation,
    double? panningBlurIntensity,
    double? speed,
    bool? reverse,
    TimelineTransition? transition,
    double? transitionDurationSeconds,
    bool? hasAudio,
    double? sourceFrameRate,
    double? sourceDurationSeconds,
    String? thumbnailPath,
    ClipTransform? transform,
    ColorGrade? colorGrade,
    ClipMotion? motion,
    ClipEffects? effects,
    ClipAnimation? animation,
    ClipAudio? audio,
    TextSpec? text,
    bool clearText = false,
    double? audioFadeInSeconds,
    double? audioFadeOutSeconds,
    bool? denoise,
    VoiceEffect? voiceEffect,
  }) {
    final nextTransform = (transform ?? this.transform).copyWith(
      x: x,
      y: y,
      scale: scale,
      opacity: opacity,
    );
    final nextColorGrade = (colorGrade ?? this.colorGrade).copyWith(
      saturation: saturation,
      brightness: brightness,
      contrast: contrast,
      gamma: gamma,
      temperature: temperature,
      tint: tint,
      highlights: highlights,
      shadows: shadows,
      fade: fade,
      vignette: vignette,
      lutId: lutId,
      clearLutId: clearLutId,
      lutIntensity: lutIntensity,
    );
    final nextMotion = (motion ?? this.motion).copyWith(
      motionBlur: motionBlur,
      motionInterpolation: motionInterpolation,
      panningBlurIntensity: panningBlurIntensity,
      speed: speed,
      reverse: reverse,
    );
    final nextEffects = (effects ?? this.effects).copyWith(
      sharpness: sharpness,
    );
    final nextAudio = (audio ?? this.audio).copyWith(
      fadeInSeconds: audioFadeInSeconds,
      fadeOutSeconds: audioFadeOutSeconds,
      denoise: denoise,
      voiceEffect: voiceEffect,
    );

    return TimelineClip(
      id: id ?? this.id,
      type: type ?? this.type,
      path: path ?? this.path,
      name: name ?? this.name,
      trackIndex: trackIndex ?? this.trackIndex,
      timelineStartSeconds: timelineStartSeconds ?? this.timelineStartSeconds,
      trimStartSeconds: trimStartSeconds ?? this.trimStartSeconds,
      trimEndSeconds: trimEndSeconds ?? this.trimEndSeconds,
      volume: volume ?? this.volume,
      enabled: enabled ?? this.enabled,
      muted: muted ?? this.muted,
      locked: locked ?? this.locked,
      transition: transition ?? this.transition,
      transitionDurationSeconds:
          transitionDurationSeconds ?? this.transitionDurationSeconds,
      hasAudio: hasAudio ?? this.hasAudio,
      sourceFrameRate: sourceFrameRate ?? this.sourceFrameRate,
      sourceDurationSeconds:
          sourceDurationSeconds ?? this.sourceDurationSeconds,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      transform: nextTransform,
      colorGrade: nextColorGrade,
      motion: nextMotion,
      effects: nextEffects,
      animation: animation ?? this.animation,
      audio: nextAudio,
      text: clearText ? null : (text ?? this.text),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'type': type.name,
      'path': path,
      'name': name,
      'trackIndex': trackIndex,
      'timelineStartSeconds': timelineStartSeconds,
      'trimStartSeconds': trimStartSeconds,
      'trimEndSeconds': trimEndSeconds,
      'volume': volume,
      'enabled': enabled,
      'muted': muted,
      'locked': locked,
      'transition': transition.name,
      'transitionDurationSeconds': transitionDurationSeconds,
      'hasAudio': hasAudio,
      'sourceFrameRate': sourceFrameRate,
      'sourceDurationSeconds': sourceDurationSeconds,
      'thumbnailPath': thumbnailPath,
      'transform': transform.toJson(),
      'colorGrade': colorGrade.toJson(),
      'motion': motion.toJson(),
      'effects': effects.toJson(),
      'animation': animation.toJson(),
      'audio': audio.toJson(),
      'text': text?.toJson(),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is TimelineClip &&
        other.id == id &&
        other.type == type &&
        other.path == path &&
        other.name == name &&
        other.trackIndex == trackIndex &&
        other.timelineStartSeconds == timelineStartSeconds &&
        other.trimStartSeconds == trimStartSeconds &&
        other.trimEndSeconds == trimEndSeconds &&
        other.volume == volume &&
        other.enabled == enabled &&
        other.muted == muted &&
        other.locked == locked &&
        other.transition == transition &&
        other.transitionDurationSeconds == transitionDurationSeconds &&
        other.hasAudio == hasAudio &&
        other.sourceFrameRate == sourceFrameRate &&
        other.sourceDurationSeconds == sourceDurationSeconds &&
        other.thumbnailPath == thumbnailPath &&
        other.transform == transform &&
        other.colorGrade == colorGrade &&
        other.motion == motion &&
        other.effects == effects &&
        other.animation == animation &&
        other.audio == audio &&
        other.text == text;
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    type,
    path,
    name,
    trackIndex,
    timelineStartSeconds,
    trimStartSeconds,
    trimEndSeconds,
    volume,
    enabled,
    muted,
    locked,
    transition,
    transitionDurationSeconds,
    hasAudio,
    sourceFrameRate,
    sourceDurationSeconds,
    thumbnailPath,
    transform,
    colorGrade,
    motion,
    effects,
    animation,
    audio,
    text,
  ]);
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
