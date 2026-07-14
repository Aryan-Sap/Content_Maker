class FfmpegSegmentNormalizer {
  const FfmpegSegmentNormalizer();

  String normalizedVideoSegment({
    required int width,
    required int height,
    required num fps,
    required String inLabel,
    required String outLabel,
    double trimStartSeconds = 0,
    double? trimDurationSeconds,
  }) {
    return '[$inLabel]'
        '${_videoTrimFilter(trimStartSeconds, trimDurationSeconds)}'
        'scale=$width:$height:force_original_aspect_ratio=decrease'
        ':flags=lanczos,'
        'pad=$width:$height:(ow-iw)/2:(oh-ih)/2:color=black,'
        'setsar=1,'
        'fps=${_number(fps)},'
        'format=yuv420p,'
        'setpts=PTS-STARTPTS'
        '[$outLabel]';
  }

  String normalizedAudioSegment({
    required int sampleRate,
    required String inLabel,
    required String outLabel,
    double trimStartSeconds = 0,
    double? trimDurationSeconds,
  }) {
    return '[$inLabel]'
        '${_audioTrimFilter(trimStartSeconds, trimDurationSeconds)}'
        'aresample=async=1:first_pts=0,'
        'aformat=sample_fmts=fltp:sample_rates=$sampleRate'
        ':channel_layouts=stereo,'
        'asetpts=PTS-STARTPTS'
        '[$outLabel]';
  }

  String timelineVideoNormalizationFilters({required num fps}) {
    return 'setsar=1,fps=${_number(fps)}';
  }

  String timelineAudioNormalizationFilters({required int sampleRate}) {
    return 'aresample=async=1:first_pts=0,'
        'aformat=sample_fmts=fltp:sample_rates=$sampleRate'
        ':channel_layouts=stereo';
  }

  String _videoTrimFilter(
    double trimStartSeconds,
    double? trimDurationSeconds,
  ) {
    if (trimStartSeconds <= 0 && trimDurationSeconds == null) {
      return '';
    }

    final duration = trimDurationSeconds;
    return 'trim=start=${_number(trimStartSeconds)}'
        '${duration == null ? '' : ':duration=${_number(duration)}'},';
  }

  String _audioTrimFilter(
    double trimStartSeconds,
    double? trimDurationSeconds,
  ) {
    if (trimStartSeconds <= 0 && trimDurationSeconds == null) {
      return '';
    }

    final duration = trimDurationSeconds;
    return 'atrim=start=${_number(trimStartSeconds)}'
        '${duration == null ? '' : ':duration=${_number(duration)}'},';
  }

  String _number(num value) {
    final text = value.toStringAsFixed(3);
    return text.replaceFirst(RegExp(r'\.?0+$'), '');
  }
}
