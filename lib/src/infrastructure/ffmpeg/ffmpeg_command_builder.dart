import '../../domain/rendering/export_settings.dart';
import '../../domain/rendering/render_job.dart';

class FfmpegCommandBuilder {
  const FfmpegCommandBuilder();

  List<String> build(ShortsRenderJob job) {
    final preset = job.preset;
    final hasAudioOverlay = _hasAudioOverlay(job);
    final filtersOriginalAudio = !hasAudioOverlay && job.sourceAudioVolume != 1;

    return <String>[
      '-y',
      '-hide_banner',
      '-nostats',
      if (job.trimStartSeconds > 0) ...['-ss', _number(job.trimStartSeconds)],
      '-i',
      job.source.path,
      if (hasAudioOverlay) ...['-i', job.audioOverlayPath!.trim()],
      if (job.trimDurationSeconds != null) ...[
        '-t',
        _number(job.trimDurationSeconds!),
      ],
      '-filter_complex',
      buildFilterGraph(job),
      '-map',
      '[v]',
      '-map',
      hasAudioOverlay ? '[a]' : '0:a?',
      if (filtersOriginalAudio) ...[
        '-filter:a',
        'volume=${_number(job.sourceAudioVolume)}',
      ],
      '-c:v',
      preset.exportSettings.videoCodec,
      '-preset',
      preset.exportSettings.encoderPreset,
      '-crf',
      '${preset.exportSettings.crf}',
      '-pix_fmt',
      'yuv420p',
      '-c:a',
      'aac',
      '-b:a',
      preset.exportSettings.audioBitrate,
      '-movflags',
      '+faststart',
      '-shortest',
      '-progress',
      'pipe:1',
      job.outputPath,
    ];
  }

  String buildFilterGraph(ShortsRenderJob job) {
    final composition = job.preset.composition;
    final settings = job.preset.exportSettings;
    final width = composition.width;
    final height = composition.height;
    final foregroundHeight = composition.foregroundHeight.clamp(1, height);
    final sharpenSecondPass = composition.sharpness / 2;
    final interpolates =
        settings.temporalSmoothing == TemporalSmoothingMode.motionInterpolation;
    final motionBlurFilter = settings.motionBlur
        ? 'tmix=frames=3:weights=\'1 2 1\','
        : '';

    // With motion interpolation the expensive minterpolate filter runs on the
    // foreground band only (before it is composed onto the full canvas); the
    // heavily blurred background gains nothing from interpolation and gets a
    // cheap fps conversion instead. This keeps both streams at the target
    // frame rate for the overlay while cutting interpolation cost roughly in
    // proportion to the saved pixel area.
    final backgroundTemporalFilter = interpolates
        ? 'fps=${settings.frameRate},'
        : '';
    final foregroundTemporalFilter = interpolates
        ? 'minterpolate='
              '${settings.interpolationQuality.minterpolateOptions(settings.frameRate)},'
        : '';
    final composedTemporalFilter = interpolates
        ? ''
        : 'fps=${settings.frameRate},';

    final background =
        '[bgsrc]scale=$width:$height:force_original_aspect_ratio=increase'
        ':flags=lanczos,'
        'crop=$width:$height,'
        '$backgroundTemporalFilter'
        '${_backgroundPanningBlurFilter(settings)}'
        '$motionBlurFilter'
        'gblur=sigma=${_number(composition.blurSigma)}'
        ':steps=${composition.blurSteps},'
        'eq=brightness=${_number(-composition.backgroundDarkness)}'
        ':saturation=${_number(composition.backgroundSaturation)},'
        'setsar=1[bg]';

    final foreground =
        '[fgsrc]scale=$width:$foregroundHeight'
        ':force_original_aspect_ratio=increase'
        ':flags=lanczos,'
        'crop=$width:$foregroundHeight,'
        '$foregroundTemporalFilter'
        'eq=contrast=${_number(composition.contrast)}'
        ':saturation=${_number(composition.foregroundSaturation)}'
        ':gamma=${_number(composition.gamma)},'
        'unsharp=5:5:${_number(composition.sharpness)}'
        ':3:3:${_number(sharpenSecondPass)},'
        'setsar=1[fg]';

    final composed =
        '[bg][fg]overlay=(W-w)/2:${composition.foregroundY},'
        '$composedTemporalFilter'
        'setsar=1,format=yuv420p[v]';

    final audio = _audioFilterGraph(job);

    return '[0:v]split=2[bgsrc][fgsrc];'
        '$background;'
        '$foreground;'
        '$composed'
        '${audio.isEmpty ? '' : ';$audio'}';
  }

  String _backgroundPanningBlurFilter(ExportSettings settings) {
    if (settings.panningBlurIntensity <= 0) {
      return '';
    }

    final kernel = 1 + (settings.panningBlurIntensity.clamp(0, 1) * 20).round();
    final oddKernel = kernel.isOdd ? kernel : kernel + 1;
    return 'avgblur=sizeX=$oddKernel:sizeY=1,';
  }

  String _audioFilterGraph(ShortsRenderJob job) {
    if (!_hasAudioOverlay(job)) {
      return '';
    }

    final sourceVolume = job.sourceAudioVolume.clamp(0, 2);
    final overlayVolume = job.overlayAudioVolume.clamp(0, 2);
    if (sourceVolume == 0) {
      return '[1:a]volume=${_number(overlayVolume)}[a]';
    }

    return '[0:a]volume=${_number(sourceVolume)}[srca];'
        '[1:a]volume=${_number(overlayVolume)}[overa];'
        '[srca][overa]amix=inputs=2:duration=longest'
        ':dropout_transition=0:normalize=0[a]';
  }

  bool _hasAudioOverlay(ShortsRenderJob job) {
    return job.audioOverlayPath?.trim().isNotEmpty ?? false;
  }

  String _number(num value) {
    final text = value.toStringAsFixed(3);
    return text.replaceFirst(RegExp(r'\.?0+$'), '');
  }
}
