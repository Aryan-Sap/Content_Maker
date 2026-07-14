import '../../domain/editing/timeline_clip.dart';
import '../../domain/rendering/export_settings.dart';

class FilterSnippets {
  const FilterSnippets._();

  static String grade(ColorGrade grade) {
    return 'eq=brightness=${_number(grade.brightness)}:'
        'saturation=${_number(grade.saturation)}:'
        'contrast=${_number(grade.contrast)}:'
        'gamma=${_number(grade.gamma)}';
  }

  static List<String> look(ColorGrade grade) {
    final filters = <String>[];
    if (grade.temperature.abs() > 0.001) {
      final kelvin = (6500 + grade.temperature * 3500).clamp(1000, 40000);
      filters.add('colortemperature=temperature=${_number(kelvin)}');
    }
    if (grade.tint.abs() > 0.001) {
      filters.add('colorbalance=gm=${_number(-grade.tint * 0.25)}');
    }
    if (grade.highlights.abs() > 0.001 ||
        grade.shadows.abs() > 0.001 ||
        grade.fade.abs() > 0.001) {
      final black = grade.fade.clamp(0.0, 0.45);
      final shadow = (0.25 + grade.shadows * 0.18 + black * 0.5).clamp(
        0.0,
        1.0,
      );
      final highlight = (0.75 + grade.highlights * 0.18).clamp(0.0, 1.0);
      filters.add(
        "curves=all='0/${_number(black)} 0.25/${_number(shadow)} "
        "0.75/${_number(highlight)} 1/1'",
      );
    }
    if (grade.vignette.abs() > 0.001) {
      final angle = (0.2 + grade.vignette.clamp(0.0, 1.0) * 1.2).clamp(
        0.2,
        1.4,
      );
      filters.add('vignette=angle=${_number(angle)}');
    }
    return filters;
  }

  static String lut(ColorGrade grade, String assetPath) {
    final lutId = grade.lutId;
    if (lutId == null || lutId.isEmpty || grade.lutIntensity <= 0.001) {
      return '';
    }
    return "lut3d='${_escapePath('$assetPath/$lutId.cube')}'";
  }

  static String reverse(ClipMotion motion) {
    return motion.reverse ? 'reverse' : '';
  }

  static String speed(ClipMotion motion) {
    if ((motion.speed - 1).abs() <= 0.001) {
      return '';
    }
    return 'setpts=PTS/${_number(motion.speed)}';
  }

  static String motionInterpolation(
    ClipMotion motion,
    int frameRate, {
    InterpolationQuality quality = InterpolationQuality.balanced,
  }) {
    if (!motion.motionInterpolation) {
      return '';
    }
    return 'minterpolate=${quality.minterpolateOptions(frameRate)}';
  }

  static String motionBlur(ClipMotion motion) {
    return motion.motionBlur ? "tmix=frames=3:weights='1 2 1'" : '';
  }

  static String panningBlur(ClipMotion motion) {
    if (motion.panningBlurIntensity <= 0) {
      return '';
    }
    var kernel = 1 + (motion.panningBlurIntensity * 20).round();
    if (kernel.isEven) {
      kernel++;
    }
    return 'avgblur=sizeX=$kernel:sizeY=1';
  }

  static String sharpness(ClipEffects effects) {
    return 'unsharp=5:5:${_number(effects.sharpness)}:5:5:0';
  }

  static String chromaKey(ChromaKeySpec chroma) {
    if (!chroma.enabled) {
      return '';
    }
    return 'chromakey=0x${chroma.colorHex}:'
        '${_number(chroma.similarity)}:${_number(chroma.blend)}';
  }

  static String drawText(TextSpec text) {
    final escapedText = text.content
        .replaceAll('\\', '\\\\')
        .replaceAll(':', '\\:')
        .replaceAll("'", "\\'");
    final shadow = text.shadow ? ':shadowcolor=black:shadowx=2:shadowy=2' : '';
    final box = text.box ? ':box=1:boxcolor=black@0.45:boxborderw=18' : '';
    final stroke = text.strokeWidth > 0
        ? ':borderw=${_number(text.strokeWidth)}:'
              'bordercolor=0x${text.strokeColorHex}'
        : '';
    return "drawtext=text='$escapedText':font='${text.font}':"
        'fontsize=${_number(text.size)}:fontcolor=0x${text.colorHex}:'
        'x=(w-text_w)/2+${_number(text.x)}:'
        'y=(h-text_h)/2+${_number(text.y)}'
        '$stroke$shadow$box';
  }

  static String blend(ClipBlendMode blendMode) {
    return switch (blendMode) {
      ClipBlendMode.normal => '',
      ClipBlendMode.screen => 'screen',
      ClipBlendMode.multiply => 'multiply',
      ClipBlendMode.overlay => 'overlay',
      ClipBlendMode.add => 'addition',
      ClipBlendMode.lighten => 'lighten',
      ClipBlendMode.darken => 'darken',
    };
  }

  static String kenBurns(ClipAnimation animation, int frameRate) {
    return switch (animation.type) {
      ClipAnimationType.kenBurnsIn =>
        'zoompan=z=min(zoom+0.0015\\,1.18):d=1:fps=$frameRate',
      ClipAnimationType.kenBurnsOut =>
        'zoompan=z=max(1.18-on*0.0015\\,1):d=1:fps=$frameRate',
      _ => '',
    };
  }

  static List<String> afade(ClipAudio audio, double durationSeconds) {
    final filters = <String>[];
    if (audio.fadeInSeconds > 0) {
      filters.add('afade=t=in:st=0:d=${_number(audio.fadeInSeconds)}');
    }
    if (audio.fadeOutSeconds > 0) {
      final start = (durationSeconds - audio.fadeOutSeconds).clamp(
        0.0,
        durationSeconds,
      );
      filters.add(
        'afade=t=out:st=${_number(start)}:d=${_number(audio.fadeOutSeconds)}',
      );
    }
    return filters;
  }

  static List<String> audioTempo(double speed) {
    if ((speed - 1).abs() <= 0.001) {
      return const [];
    }
    var remaining = speed.clamp(0.1, 100.0);
    final filters = <String>[];
    while (remaining > 2.0) {
      filters.add('atempo=2');
      remaining /= 2;
    }
    while (remaining < 0.5) {
      filters.add('atempo=0.5');
      remaining /= 0.5;
    }
    filters.add('atempo=${_number(remaining)}');
    return filters;
  }

  static String duck({
    required String voiceLabel,
    required String musicLabel,
    required String outputLabel,
  }) {
    return '[$musicLabel][$voiceLabel]sidechaincompress='
        'threshold=0.08:ratio=8:attack=20:release=250[$outputLabel]';
  }

  static String _escapePath(String path) {
    return path
        .replaceAll('\\', '/')
        .replaceAll(':', '\\:')
        .replaceAll("'", r"\'");
  }

  static String _number(num value) {
    final text = value.toStringAsFixed(3);
    return text.replaceFirst(RegExp(r'\.?0+$'), '');
  }
}
