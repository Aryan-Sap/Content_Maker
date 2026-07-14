import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../../domain/editing/manual_render_job.dart';
import '../../domain/editing/timeline_clip.dart';
import '../../domain/rendering/concat_merge_job.dart';
import '../../domain/rendering/render_preset.dart';
import 'ffmpeg_concat_command_builder.dart';
import 'ffmpeg_segment_normalizer.dart';
import 'filter_snippets.dart';

class FfmpegManualTimelineCommandBuilder {
  const FfmpegManualTimelineCommandBuilder({
    this.concatCommandBuilder = const FfmpegConcatCommandBuilder(),
    this.segmentNormalizer = const FfmpegSegmentNormalizer(),
    this.lutAssetDirectory,
  });

  final FfmpegConcatCommandBuilder concatCommandBuilder;
  final FfmpegSegmentNormalizer segmentNormalizer;
  final String? lutAssetDirectory;

  List<String> build(ManualRenderJob job) {
    final concatJob = _sequentialConcatJob(job);
    if (concatJob != null) {
      return concatCommandBuilder.build(concatJob);
    }

    final clips = _activeClips(job);
    final hasAudio = job.project.audibleAudioClips.isNotEmpty;

    return <String>[
      '-y',
      '-hide_banner',
      '-nostats',
      for (final clip in clips) ...['-i', clip.path],
      '-filter_complex',
      buildFilterGraph(job),
      '-map',
      '[v]',
      if (hasAudio) ...['-map', '[a]'] else '-an',
      '-c:v',
      'libx264',
      '-preset',
      'medium',
      '-crf',
      '18',
      '-pix_fmt',
      'yuv420p',
      if (hasAudio) ...['-c:a', 'aac', '-b:a', '192k'],
      '-movflags',
      '+faststart',
      '-shortest',
      '-progress',
      'pipe:1',
      job.project.outputPath,
    ];
  }

  String buildFilterGraph(ManualRenderJob job) {
    final concatJob = _sequentialConcatJob(job);
    if (concatJob != null) {
      return concatCommandBuilder.buildFilterGraph(concatJob);
    }

    final project = job.project;
    final clips = _activeClips(job);
    final inputIndexByClipId = <String, int>{
      for (var i = 0; i < clips.length; i++) clips[i].id: i,
    };
    final graph = StringBuffer()
      ..write(
        'color=c=0x${project.backgroundHexColor}:'
        's=${project.width}x${project.height}:'
        'd=${_number(project.durationSeconds)},format=rgba[base0]',
      );

    final videoClips =
        project.enabledVideoClips.where((clip) => clip.opacity > 0).toList()
          ..sort(_compareVisualStack);

    var baseLabel = 'base0';
    for (var i = 0; i < videoClips.length; i++) {
      final clip = videoClips[i];
      final transitionHoldSeconds = _transitionHoldSeconds(clip, videoClips);
      // Prefer covering the transition overlap with real source footage; only
      // freeze the last frame (tpad) for whatever the source cannot supply.
      final realHoldSeconds = _holdFootageSeconds(clip, transitionHoldSeconds);
      final frozenHoldSeconds = math.max(
        0.0,
        transitionHoldSeconds - realHoldSeconds,
      );
      final visualEndSeconds = clip.timelineEndSeconds + transitionHoldSeconds;
      final inputIndex = inputIndexByClipId[clip.id]!;
      final clipLabel = 'clipv$i';
      final foregroundSourceLabel = project.blurredBackgroundEnabled
          ? 'clipfgsrc$i'
          : '$inputIndex:v';
      final nextBaseLabel = 'base${i + 1}';
      final x = '(${project.width}-w)/2+${_number(clip.x * project.width / 2)}';
      final y =
          '(${project.height}-h)/2+${_number(clip.y * project.height / 2)}';

      graph.write(';');
      if (project.blurredBackgroundEnabled) {
        final blurredLabel = 'clipbg$i';
        final blurredBaseLabel = 'base${i}b';
        graph
          ..write('[$inputIndex:v]')
          ..write(_videoTrimFilter(clip, extraTimelineSeconds: realHoldSeconds))
          ..write(
            ',${segmentNormalizer.timelineVideoNormalizationFilters(fps: project.frameRate)}',
          )
          ..write(_videoProcessingFilters(clip, project.frameRate))
          ..write(_transitionHoldFilter(frozenHoldSeconds))
          ..write(',')
          ..write('${_timelineSetptsFilter(clip)},')
          ..write('split=2[clipbgsrc$i][clipfgsrc$i];')
          ..write('[clipbgsrc$i]')
          ..write(
            'scale=${project.width}:${project.height}:'
            'force_original_aspect_ratio=increase:flags=lanczos,',
          )
          ..write('crop=${project.width}:${project.height},')
          ..write('gblur=sigma=28:steps=2,format=rgba,')
          ..write('colorchannelmixer=aa=0.72')
          ..write('[$blurredLabel];')
          ..write('[$baseLabel][$blurredLabel]')
          ..write(
            "overlay=0:0:enable='between(t,"
            '${_number(clip.timelineStartSeconds)},'
            "${_number(visualEndSeconds)})':"
            'eof_action=pass:shortest=0',
          )
          ..write('[$blurredBaseLabel];');
        baseLabel = blurredBaseLabel;
      }

      graph
        ..write('[$foregroundSourceLabel]')
        ..write(
          project.blurredBackgroundEnabled
              ? ''
              : _videoTrimFilter(clip, extraTimelineSeconds: realHoldSeconds),
        )
        ..write(
          project.blurredBackgroundEnabled
              ? ''
              : ',${segmentNormalizer.timelineVideoNormalizationFilters(fps: project.frameRate)}',
        )
        ..write(
          project.blurredBackgroundEnabled
              ? ''
              : _videoProcessingFilters(clip, project.frameRate),
        )
        ..write(
          project.blurredBackgroundEnabled
              ? ''
              : _transitionHoldFilter(frozenHoldSeconds),
        )
        ..write(project.blurredBackgroundEnabled ? '' : ',')
        ..write(
          project.blurredBackgroundEnabled
              ? ''
              : '${_timelineSetptsFilter(clip)},',
        )
        ..write('scale=iw*${_number(clip.scale)}:ih*${_number(clip.scale)}')
        ..write(':flags=lanczos,format=rgba')
        ..write(_transitionFilter(clip, videoClips))
        ..write(',')
        ..write('colorchannelmixer=aa=${_number(clip.opacity)}')
        ..write('[$clipLabel];')
        ..write('[$baseLabel][$clipLabel]')
        ..write(
          'overlay=x=${_transitionX(clip, x, project.width)}:'
          'y=${_transitionY(clip, y, project.height)}:'
          "enable='between(t,${_number(clip.timelineStartSeconds)},"
          "${_number(visualEndSeconds)})':"
          'eof_action=pass:shortest=0',
        )
        ..write('[$nextBaseLabel]');
      baseLabel = nextBaseLabel;
    }

    graph
      ..write(';')
      ..write('[$baseLabel]fps=${project.frameRate},format=yuv420p[v]');

    final audioGraph = _audioFilterGraph(job, inputIndexByClipId);
    if (audioGraph.isNotEmpty) {
      graph
        ..write(';')
        ..write(audioGraph);
    }

    return graph.toString();
  }

  List<TimelineClip> _activeClips(ManualRenderJob job) {
    return job.project.clips
        .where((clip) => clip.enabled && clip.durationSeconds > 0)
        .toList();
  }

  int _compareVisualStack(TimelineClip a, TimelineClip b) {
    if (_transitionFollows(a, b)) {
      return -1;
    }
    if (_transitionFollows(b, a)) {
      return 1;
    }
    final trackComparison = a.trackIndex.compareTo(b.trackIndex);
    if (trackComparison != 0) {
      return trackComparison;
    }
    return a.timelineStartSeconds.compareTo(b.timelineStartSeconds);
  }

  bool _transitionFollows(TimelineClip outgoing, TimelineClip incoming) {
    return _overlapsPredecessor(incoming.transition) &&
        _areAdjacent(outgoing, incoming);
  }

  bool _areAdjacent(TimelineClip outgoing, TimelineClip incoming) {
    return (incoming.timelineStartSeconds - outgoing.timelineEndSeconds).abs() <=
        0.08;
  }

  /// Whether an incoming transition plays on top of the (held) previous clip.
  /// Every transition overlaps except a hard cut and fade-through-black,
  /// which fades the outgoing clip out before the boundary instead.
  bool _overlapsPredecessor(TimelineTransition transition) {
    return transition != TimelineTransition.cut &&
        transition != TimelineTransition.fadeThroughBlack;
  }

  String _videoTrimFilter(
    TimelineClip clip, {
    double extraTimelineSeconds = 0,
  }) {
    final speed = clip.speed.clamp(0.1, 100.0);
    final duration =
        clip.sourceTrimDurationSeconds + extraTimelineSeconds * speed;
    return 'trim=start=${_number(clip.trimStartSeconds)}:'
        'duration=${_number(duration)}';
  }

  /// How much of [holdSeconds] (timeline time) can be covered with real
  /// source footage past the clip's trim end.
  double _holdFootageSeconds(TimelineClip clip, double holdSeconds) {
    if (holdSeconds <= 0) {
      return 0;
    }
    final sourceDuration = clip.sourceDurationSeconds;
    if (sourceDuration == null) {
      return 0;
    }
    final speed = clip.speed.clamp(0.1, 100.0);
    final availableSourceSeconds = math.max(
      0.0,
      sourceDuration - clip.trimEndSeconds,
    );
    return math.min(holdSeconds, availableSourceSeconds / speed);
  }

  String _videoProcessingFilters(TimelineClip clip, int frameRate) {
    final filters = <String>[
      FilterSnippets.reverse(clip.motion),
      FilterSnippets.motionInterpolation(clip.motion, frameRate),
      FilterSnippets.motionBlur(clip.motion),
      FilterSnippets.panningBlur(clip.motion),
      FilterSnippets.grade(clip.colorGrade),
      ...FilterSnippets.look(clip.colorGrade),
      FilterSnippets.lut(clip.colorGrade, _resolvedLutAssetDirectory()),
      FilterSnippets.sharpness(clip.effects),
      FilterSnippets.chromaKey(clip.effects.chromaKey),
      FilterSnippets.kenBurns(clip.animation, frameRate),
    ].where((filter) => filter.isNotEmpty);
    return filters.map((filter) => ',$filter').join();
  }

  String _timelineSetptsFilter(TimelineClip clip) {
    final speed = clip.speed.clamp(0.1, 100.0);
    return 'setpts=(PTS-STARTPTS)/${_number(speed)}+'
        '${_number(clip.timelineStartSeconds)}/TB';
  }

  String _resolvedLutAssetDirectory() {
    final configuredDirectory = lutAssetDirectory;
    if (configuredDirectory != null) {
      return configuredDirectory;
    }
    final sourceTreeDirectory = Directory(p.join('assets', 'luts'));
    if (sourceTreeDirectory.existsSync()) {
      return p.absolute(sourceTreeDirectory.path);
    }
    return p.join(
      p.dirname(Platform.resolvedExecutable),
      'data',
      'flutter_assets',
      'assets',
      'luts',
    );
  }

  /// Entry effect for [clip]'s own transition plus the exit effect requested
  /// by an adjacent follower (fade-through-black fades the outgoing clip out;
  /// circle-close irises the outgoing clip shut while the next one appears).
  String _transitionFilter(TimelineClip clip, List<TimelineClip> videoClips) {
    final filters = StringBuffer();
    if (clip.transition != TimelineTransition.cut &&
        clip.timelineStartSeconds > 0) {
      final start = _number(clip.timelineStartSeconds);
      final rawDuration = clip.transitionDurationSeconds;
      final duration = _number(rawDuration);
      switch (clip.transition) {
        case TimelineTransition.dissolve:
        case TimelineTransition.circleClose:
          filters.write(',fade=t=in:st=$start:d=$duration:alpha=1');
        case TimelineTransition.fadeThroughBlack:
          filters.write(',fade=t=in:st=$start:d=${_number(rawDuration / 2)}');
        case TimelineTransition.circleOpen:
          filters.write(
            ",vignette=angle='(PI/2)*max(0\\,1-(t-$start)/$duration)'"
            ':eval=frame',
          );
        case TimelineTransition.zoomIn:
          filters
            ..write(',fade=t=in:st=$start:d=$duration:alpha=1')
            ..write(_zoomScaleFilter(start, duration, fromFactor: 0.25));
        case TimelineTransition.zoomOut:
          filters
            ..write(',fade=t=in:st=$start:d=$duration:alpha=1')
            ..write(_zoomScaleFilter(start, duration, fromFactor: -0.2));
        case TimelineTransition.slideLeft:
        case TimelineTransition.slideRight:
        case TimelineTransition.slideUp:
        case TimelineTransition.slideDown:
        case TimelineTransition.wipeLeft:
        case TimelineTransition.wipeRight:
        case TimelineTransition.wipeUp:
        case TimelineTransition.wipeDown:
        case TimelineTransition.whipPan:
        case TimelineTransition.cut:
          break;
      }
    }

    final follower = _adjacentFollowerWithTransition(clip, videoClips);
    if (follower != null) {
      final boundary = follower.timelineStartSeconds;
      final rawDuration = follower.transitionDurationSeconds;
      switch (follower.transition) {
        case TimelineTransition.fadeThroughBlack:
          filters.write(
            ',fade=t=out:st=${_number(boundary - rawDuration / 2)}'
            ':d=${_number(rawDuration / 2)}',
          );
        case TimelineTransition.circleClose:
          filters.write(
            ",vignette=angle='(PI/2)*min(1\\,max(0\\,"
            "(t-${_number(boundary)})/${_number(rawDuration)}))':eval=frame",
          );
        default:
          break;
      }
    }
    return filters.toString();
  }

  /// Animated zoom on the incoming clip: scales from `1 + fromFactor` down
  /// (or up, for negative factors) to 1 over the transition window.
  String _zoomScaleFilter(
    String start,
    String duration, {
    required double fromFactor,
  }) {
    final factor =
        '(1+${_number(fromFactor)}*max(0\\,1-(t-$start)/$duration))';
    return ',scale=w=iw*$factor:h=ih*$factor:eval=frame';
  }

  TimelineClip? _adjacentFollowerWithTransition(
    TimelineClip outgoing,
    List<TimelineClip> videoClips,
  ) {
    for (final incoming in videoClips) {
      if (incoming.id == outgoing.id ||
          incoming.transition == TimelineTransition.cut ||
          incoming.timelineStartSeconds <= 0) {
        continue;
      }
      if (_areAdjacent(outgoing, incoming)) {
        return incoming;
      }
    }
    return null;
  }

  double _transitionHoldSeconds(
    TimelineClip outgoing,
    List<TimelineClip> videoClips,
  ) {
    for (final incoming in videoClips) {
      if (incoming.id == outgoing.id ||
          !_overlapsPredecessor(incoming.transition) ||
          incoming.timelineStartSeconds <= 0) {
        continue;
      }
      if (_areAdjacent(outgoing, incoming)) {
        return incoming.transitionDurationSeconds;
      }
    }
    return 0;
  }

  String _transitionHoldFilter(double durationSeconds) {
    if (durationSeconds <= 0) {
      return '';
    }
    return ',tpad=stop_mode=clone:stop_duration=${_number(durationSeconds)}';
  }

  String _transitionX(TimelineClip clip, String baseX, int canvasWidth) {
    if (clip.timelineStartSeconds <= 0) {
      return baseX;
    }
    final start = _number(clip.timelineStartSeconds);
    final duration = _number(clip.transitionDurationSeconds);
    final remaining = _transitionRemainingExpr(start, duration);
    return switch (clip.transition) {
      TimelineTransition.slideLeft ||
      TimelineTransition.wipeLeft ||
      TimelineTransition.whipPan => '($baseX)+$remaining*$canvasWidth',
      TimelineTransition.slideRight ||
      TimelineTransition.wipeRight => '($baseX)-$remaining*$canvasWidth',
      _ => baseX,
    };
  }

  String _transitionY(TimelineClip clip, String baseY, int canvasHeight) {
    if (clip.timelineStartSeconds <= 0) {
      return baseY;
    }
    final start = _number(clip.timelineStartSeconds);
    final duration = _number(clip.transitionDurationSeconds);
    final remaining = _transitionRemainingExpr(start, duration);
    return switch (clip.transition) {
      TimelineTransition.slideUp ||
      TimelineTransition.wipeUp => '($baseY)+$remaining*$canvasHeight',
      TimelineTransition.slideDown ||
      TimelineTransition.wipeDown => '($baseY)-$remaining*$canvasHeight',
      _ => baseY,
    };
  }

  String _transitionRemainingExpr(String start, String duration) {
    final progress = '(max(0\\,min(1\\,(t-$start)/$duration)))';
    return '(1-$progress*$progress*(3-2*$progress))';
  }

  String _audioFilterGraph(
    ManualRenderJob job,
    Map<String, int> inputIndexByClipId,
  ) {
    final audioClips = job.project.audibleAudioClips
      ..sort(
        (a, b) => a.timelineStartSeconds.compareTo(b.timelineStartSeconds),
      );
    if (audioClips.isEmpty) {
      return '';
    }

    final graph = StringBuffer();
    for (var i = 0; i < audioClips.length; i++) {
      final clip = audioClips[i];
      final inputIndex = inputIndexByClipId[clip.id]!;
      final delayMs = (clip.timelineStartSeconds * 1000).round();
      graph
        ..write('[$inputIndex:a]')
        ..write('atrim=start=${_number(clip.trimStartSeconds)}')
        ..write(':duration=${_number(clip.sourceTrimDurationSeconds)},')
        ..write(
          segmentNormalizer.timelineAudioNormalizationFilters(
            sampleRate: FfmpegConcatCommandBuilder.audioSampleRate,
          ),
        )
        ..write(',')
        ..write('asetpts=PTS-STARTPTS,');
      if (clip.reverse) {
        graph.write('areverse,asetpts=PTS-STARTPTS,');
      }
      for (final tempoFilter in FilterSnippets.audioTempo(clip.speed)) {
        graph.write('$tempoFilter,');
      }
      graph.write('volume=${_number(clip.volume)},');
      for (final fadeFilter in FilterSnippets.afade(
        clip.audio,
        clip.durationSeconds,
      )) {
        graph.write('$fadeFilter,');
      }
      graph
        ..write('adelay=$delayMs:all=1')
        ..write('[clipa$i];');
    }

    for (var i = 0; i < audioClips.length; i++) {
      graph.write('[clipa$i]');
    }
    graph.write(
      'amix=inputs=${audioClips.length}:duration=longest:'
      'dropout_transition=0:normalize=0[a]',
    );

    return graph.toString();
  }

  String _number(num value) {
    final text = value.toStringAsFixed(3);
    return text.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  ConcatMergeJob? _sequentialConcatJob(ManualRenderJob job) {
    final project = job.project;
    final videoClips = project.enabledVideoClips.toList()
      ..sort(
        (a, b) => a.timelineStartSeconds.compareTo(b.timelineStartSeconds),
      );
    if (videoClips.length < 2 ||
        project.blurredBackgroundEnabled ||
        project.audibleAudioClips.isNotEmpty) {
      return null;
    }

    final trackIndex = videoClips.first.trackIndex;
    var expectedStart = 0.0;
    for (final clip in videoClips) {
      if (clip.trackIndex != trackIndex ||
          !_isSequentialMergeClip(clip) ||
          (clip.timelineStartSeconds - expectedStart).abs() > 0.08) {
        return null;
      }
      expectedStart = clip.timelineEndSeconds;
    }

    final preset = RenderPreset.gameplayShort.copyWith(
      composition: RenderPreset.gameplayShort.composition.copyWith(
        width: project.width,
        height: project.height,
        foregroundHeight: project.height,
      ),
      exportSettings: RenderPreset.gameplayShort.exportSettings.copyWith(
        frameRate: project.frameRate,
        crf: 18,
      ),
    );

    return ConcatMergeJob(
      inputs: [
        for (final clip in videoClips)
          ConcatMergeInput(
            path: clip.path,
            durationSeconds: clip.sourceDurationSeconds ?? clip.trimEndSeconds,
            hasAudio: clip.hasAudio,
            trimStartSeconds: clip.trimStartSeconds,
            trimEndSeconds: clip.trimEndSeconds,
          ),
      ],
      outputPath: project.outputPath,
      preset: preset,
    );
  }

  bool _isSequentialMergeClip(TimelineClip clip) {
    return clip.transition == TimelineTransition.cut &&
        clip.transform.isDefault &&
        clip.colorGrade.isDefault &&
        clip.motion.isDefault &&
        clip.effects.isDefault &&
        clip.animation.isDefault &&
        clip.audio.isDefault &&
        clip.text == null;
  }
}
