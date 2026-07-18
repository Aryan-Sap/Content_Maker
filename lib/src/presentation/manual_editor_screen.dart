import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../application/create_manual_timeline_export.dart';
import '../application/project_store.dart';
import '../domain/editing/manual_edit_project.dart';
import '../domain/editing/manual_render_job.dart';
import '../domain/editing/timeline_clip.dart';
import '../domain/rendering/render_job.dart';
import '../infrastructure/ffmpeg/ffmpeg_executables.dart';
import '../infrastructure/ffmpeg/ffmpeg_media_probe.dart';
import '../infrastructure/ffmpeg/ffmpeg_manual_timeline_processor.dart';
import '../infrastructure/ffmpeg/filter_snippets.dart';
import '../infrastructure/notifications/desktop_notifier.dart';
import 'publishing/publish_panel.dart';
import 'widgets/frame_stream_player.dart';
import 'widgets/rendered_clip_player.dart';

enum _ManualCanvasPreset { vertical, square, landscape }

enum _EditorView { edit, preview }

enum _TimelineClipAction {
  trimStartToCursor,
  split,
  trimEndToCursor,
  duplicate,
  delete,
}

sealed class _TimelineDragPayload {
  const _TimelineDragPayload();
}

class _MediaClipDragPayload extends _TimelineDragPayload {
  const _MediaClipDragPayload(this.clip);

  final TimelineClip clip;
}

class _TransitionDragPayload extends _TimelineDragPayload {
  const _TransitionDragPayload(this.transition, {this.sourceClipId});

  final TimelineTransition transition;
  final String? sourceClipId;
}

extension _ManualCanvasPresetDetails on _ManualCanvasPreset {
  String get label {
    return switch (this) {
      _ManualCanvasPreset.vertical => 'Short',
      _ManualCanvasPreset.square => 'Square',
      _ManualCanvasPreset.landscape => 'Wide',
    };
  }

  IconData get icon {
    return switch (this) {
      _ManualCanvasPreset.vertical => Icons.crop_portrait_outlined,
      _ManualCanvasPreset.square => Icons.crop_square_outlined,
      _ManualCanvasPreset.landscape => Icons.crop_16_9_outlined,
    };
  }

  int get width {
    return switch (this) {
      _ManualCanvasPreset.vertical => 1080,
      _ManualCanvasPreset.square => 1080,
      _ManualCanvasPreset.landscape => 1920,
    };
  }

  int get height {
    return switch (this) {
      _ManualCanvasPreset.vertical => 1920,
      _ManualCanvasPreset.square => 1080,
      _ManualCanvasPreset.landscape => 1080,
    };
  }
}

extension _EditorViewDetails on _EditorView {
  String get label {
    return switch (this) {
      _EditorView.edit => 'Edit',
      _EditorView.preview => 'Preview',
    };
  }

  IconData get icon {
    return switch (this) {
      _EditorView.edit => Icons.edit_outlined,
      _EditorView.preview => Icons.play_circle_outline,
    };
  }
}

class ManualEditorScreen extends StatefulWidget {
  const ManualEditorScreen({required this.desktopRendererAvailable, super.key});

  final bool desktopRendererAvailable;

  @override
  State<ManualEditorScreen> createState() => _ManualEditorScreenState();
}

class _ManualEditorScreenState extends State<ManualEditorScreen> {
  static const _filePickerChannel = MethodChannel('content_maker/file_picker');

  final _outputController = TextEditingController();
  final _playbackFocusNode = FocusNode();
  final _mediaProbe = const FfmpegMediaProbe();
  final _exportUseCase = const CreateManualTimelineExport(
    FfmpegManualTimelineProcessor(),
  );
  final _projectStore = const ProjectStore();

  StreamSubscription<RenderProgress>? _renderSubscription;
  Timer? _previewPlaybackTimer;
  Timer? _previewSeekRestartTimer;
  final List<Process> _previewAudioProcesses = [];
  final List<Timer> _previewAudioTimers = [];
  final List<TimelineClip> _clips = [];
  final List<ManualEditProject> _undoStack = [];
  final List<ManualEditProject> _redoStack = [];
  _ManualCanvasPreset _canvasPreset = _ManualCanvasPreset.vertical;
  _EditorView _editorView = _EditorView.edit;
  String? _selectedClipId;
  double _playheadSeconds = 0;
  int _previewSeekVersion = 0;
  double? _progress;
  String _status = 'Manual editor ready.';
  bool _isRendering = false;
  bool _isPreviewPlaying = false;
  bool _blurredBackgroundEnabled = true;

  bool get _canUndo => _undoStack.isNotEmpty && !_isRendering;

  bool get _canRedo => _redoStack.isNotEmpty && !_isRendering;

  TimelineClip? get _selectedClip {
    for (final clip in _clips) {
      if (clip.id == _selectedClipId) {
        return clip;
      }
    }
    return null;
  }

  TimelineClip? _clipById(String clipId) {
    for (final clip in _clips) {
      if (clip.id == clipId) {
        return clip;
      }
    }
    return null;
  }

  double get _timelineDuration {
    var end = 10.0;
    for (final clip in _clips) {
      end = math.max(end, clip.timelineEndSeconds + 2);
    }
    return end;
  }

  bool get _canChooseMedia => Platform.isWindows && !_isRendering;

  bool get _canExport {
    return !_isRendering &&
        widget.desktopRendererAvailable &&
        _outputController.text.trim().isNotEmpty &&
        _clips.any((clip) => clip.isVideo && clip.enabled);
  }

  @override
  void dispose() {
    _renderSubscription?.cancel();
    _previewPlaybackTimer?.cancel();
    _previewSeekRestartTimer?.cancel();
    _stopPreviewAudio();
    _playbackFocusNode.dispose();
    _outputController.dispose();
    super.dispose();
  }

  String _cleanPath(String value) {
    var path = value.trim();
    while (path.length >= 2) {
      final startsWithDoubleQuote = path.startsWith('"');
      final startsWithSingleQuote = path.startsWith("'");
      final endsWithDoubleQuote = path.endsWith('"');
      final endsWithSingleQuote = path.endsWith("'");

      if ((startsWithDoubleQuote && endsWithDoubleQuote) ||
          (startsWithSingleQuote && endsWithSingleQuote)) {
        path = path.substring(1, path.length - 1).trim();
      } else {
        break;
      }
    }
    return path;
  }

  String _suggestedOutputPath(String sourcePath) {
    final directory = p.dirname(sourcePath);
    final basename = p.basenameWithoutExtension(sourcePath);
    return p.join(directory, '${basename}_manual_edit.mp4');
  }

  Future<void> _addClip(TimelineClipType type) async {
    if (!_canChooseMedia) {
      return;
    }

    try {
      final selectedPath = await _filePickerChannel.invokeMethod<String>(
        type == TimelineClipType.video ? 'pickVideo' : 'pickAudio',
      );
      if (!mounted || selectedPath == null || selectedPath.trim().isEmpty) {
        return;
      }

      final path = _cleanPath(selectedPath);
      final trackIndex = _defaultTrackIndex(type);
      final clip = TimelineClip.fromPath(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        type: type,
        path: path,
        timelineStartSeconds: type == TimelineClipType.video
            ? _nextVideoClipStart(trackIndex)
            : _playheadSeconds,
        durationSeconds: type == TimelineClipType.video
            ? TimelineClip.defaultVideoDurationSeconds
            : TimelineClip.defaultAudioDurationSeconds,
        trackIndex: trackIndex,
      );

      _recordHistory();
      setState(() {
        _clips.add(clip);
        _selectedClipId = clip.id;
        if (type == TimelineClipType.video &&
            _outputController.text.trim().isEmpty) {
          _outputController.text = _suggestedOutputPath(path);
        }
        _status = type == TimelineClipType.video
            ? 'Video clip added.'
            : 'Audio clip added.';
        _progress = null;
      });
      unawaited(_probeMediaMetadata(clip));
      if (type == TimelineClipType.video) {
        unawaited(_generateThumbnail(clip));
      }
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _status = error.message ?? 'Could not open the media picker.';
        _progress = null;
      });
    }
  }

  Future<void> _generateThumbnail(TimelineClip clip) async {
    try {
      final thumbnailDirectory = Directory(
        p.join(Directory.systemTemp.path, 'content_maker_thumbnails'),
      );
      await thumbnailDirectory.create(recursive: true);
      final outputPath = p.join(thumbnailDirectory.path, '${clip.id}.jpg');
      final result = await Process.run(FfmpegExecutables.ffmpeg, <String>[
        '-y',
        '-hide_banner',
        '-loglevel',
        'error',
        '-ss',
        '0',
        '-i',
        clip.path,
        '-frames:v',
        '1',
        '-vf',
        'scale=640:-1',
        outputPath,
      ]);

      if (!mounted || result.exitCode != 0 || !File(outputPath).existsSync()) {
        return;
      }

      final index = _clips.indexWhere((item) => item.id == clip.id);
      if (index == -1) {
        return;
      }

      setState(() {
        _clips[index] = _clips[index].copyWith(thumbnailPath: outputPath);
      });
    } catch (_) {
      return;
    }
  }

  Future<void> _probeMediaMetadata(TimelineClip clip) async {
    try {
      final metadata = await _mediaProbe.probe(clip.path);
      if (!mounted ||
          (metadata.durationSeconds == null && metadata.frameRate == null)) {
        return;
      }
      final detectedFrameRate = metadata.frameRate
          ?.clamp(1.0, 120.0)
          .toDouble();

      final index = _clips.indexWhere((item) => item.id == clip.id);
      if (index == -1) {
        return;
      }

      setState(() {
        final current = _clips[index];
        final previousTimelineEnd = current.timelineEndSeconds;
        final sourceDurationSeconds = metadata.durationSeconds;
        final shouldUseFullSourceDuration =
            sourceDurationSeconds != null &&
            current.sourceDurationSeconds == null &&
            current.trimStartSeconds == 0 &&
            ((current.isVideo &&
                    (current.trimEndSeconds -
                                TimelineClip.defaultVideoDurationSeconds)
                            .abs() <
                        0.001) ||
                (current.isAudio &&
                    (current.trimEndSeconds -
                                TimelineClip.defaultAudioDurationSeconds)
                            .abs() <
                        0.001));
        final trimEnd = sourceDurationSeconds == null
            ? current.trimEndSeconds
            : shouldUseFullSourceDuration
            ? sourceDurationSeconds
            : current.trimEndSeconds
                  .clamp(0.1, math.max(0.1, sourceDurationSeconds))
                  .toDouble();
        final updated = _normalizeClip(
          current.copyWith(
            sourceFrameRate: detectedFrameRate,
            sourceDurationSeconds: sourceDurationSeconds,
            hasAudio: metadata.hasAudio,
            trimEndSeconds: trimEnd,
          ),
        );
        _clips[index] = updated;
        _rippleFollowersFromBoundary(
          current,
          previousTimelineEnd,
          updated.timelineEndSeconds,
        );
      });
    } catch (_) {
      return;
    }
  }

  int _defaultTrackIndex(TimelineClipType type) {
    final sameTypeClips = _clips.where((clip) => clip.type == type);
    if (sameTypeClips.isEmpty) {
      return 0;
    }
    return sameTypeClips.map((clip) => clip.trackIndex).fold<int>(0, math.max);
  }

  double _nextVideoClipStart(int trackIndex) {
    var end = 0.0;
    for (final clip in _clips.where(
      (clip) => clip.isVideo && clip.trackIndex == trackIndex,
    )) {
      end = math.max(end, clip.timelineEndSeconds);
    }
    return end;
  }

  void _selectClip(String clipId) {
    final clip = _clips.firstWhere((clip) => clip.id == clipId);
    setState(() {
      _selectedClipId = clipId;
      if (!_isPlayheadInside(clip)) {
        _playheadSeconds = clip.timelineStartSeconds;
      }
    });
  }

  bool _isPlayheadInside(TimelineClip clip) {
    return _playheadSeconds >= clip.timelineStartSeconds &&
        _playheadSeconds <= clip.timelineEndSeconds;
  }

  void _updateClip(String clipId, TimelineClip Function(TimelineClip) update) {
    final index = _clips.indexWhere((clip) => clip.id == clipId);
    if (index == -1) {
      return;
    }

    final currentClip = _clips[index];
    final updatedClip = update(currentClip);
    final onlyLockChanged =
        updatedClip.locked != currentClip.locked &&
        updatedClip == currentClip.copyWith(locked: updatedClip.locked);
    if (currentClip.locked && !onlyLockChanged) {
      return;
    }
    if (updatedClip == currentClip) {
      return;
    }

    _recordHistory();
    setState(() {
      _clips[index] = _normalizeClip(updatedClip);
      _playheadSeconds = _playheadSeconds
          .clamp(0.0, _timelineDuration)
          .toDouble();
      _previewSeekVersion++;
    });
  }

  TimelineClip _normalizeClip(TimelineClip clip) {
    final sourceDuration = math.max(clip.sourceDurationSeconds ?? 3600.0, 0.1);
    final trimStart = clip.trimStartSeconds
        .clamp(0.0, math.max(0.0, sourceDuration - 0.1))
        .toDouble();
    final trimEnd = math.max(trimStart + 0.1, clip.trimEndSeconds);
    return clip.copyWith(
      trackIndex: clip.trackIndex.clamp(0, 5).toInt(),
      timelineStartSeconds: clip.timelineStartSeconds.clamp(0.0, 3600.0),
      trimStartSeconds: trimStart,
      trimEndSeconds: trimEnd.clamp(trimStart + 0.1, sourceDuration).toDouble(),
      x: clip.x.clamp(-1.5, 1.5).toDouble(),
      y: clip.y.clamp(-1.5, 1.5).toDouble(),
      scale: clip.scale.clamp(0.1, 3.0).toDouble(),
      opacity: clip.opacity.clamp(0.0, 1.0).toDouble(),
      volume: clip.volume.clamp(0.0, 2.0).toDouble(),
      saturation: clip.saturation.clamp(0.0, 2.0).toDouble(),
      brightness: clip.brightness.clamp(-0.5, 0.5).toDouble(),
      contrast: clip.contrast.clamp(0.5, 2.0).toDouble(),
      gamma: clip.gamma.clamp(0.5, 2.0).toDouble(),
      temperature: clip.temperature.clamp(-1.0, 1.0).toDouble(),
      tint: clip.tint.clamp(-1.0, 1.0).toDouble(),
      highlights: clip.highlights.clamp(-1.0, 1.0).toDouble(),
      shadows: clip.shadows.clamp(-1.0, 1.0).toDouble(),
      fade: clip.fade.clamp(0.0, 1.0).toDouble(),
      vignette: clip.vignette.clamp(0.0, 1.0).toDouble(),
      lutIntensity: clip.lutIntensity.clamp(0.0, 1.0).toDouble(),
      sharpness: clip.sharpness.clamp(0.0, 1.5).toDouble(),
      panningBlurIntensity: clip.panningBlurIntensity
          .clamp(0.0, 1.0)
          .toDouble(),
      speed: clip.speed.clamp(0.1, 100.0).toDouble(),
      audioFadeInSeconds: clip.audioFadeInSeconds
          .clamp(0.0, clip.durationSeconds)
          .toDouble(),
      audioFadeOutSeconds: clip.audioFadeOutSeconds
          .clamp(0.0, clip.durationSeconds)
          .toDouble(),
      transitionDurationSeconds: clip.transitionDurationSeconds
          .clamp(0.1, math.max(0.1, clip.durationSeconds / 2))
          .toDouble(),
    );
  }

  void _moveClipOnCanvas(String clipId, Offset normalizedDelta) {
    _updateClip(
      clipId,
      (clip) => clip.copyWith(
        x: clip.x + normalizedDelta.dx,
        y: clip.y + normalizedDelta.dy,
      ),
    );
  }

  void _moveClipOnTimeline(String clipId, double deltaSeconds) {
    _updateClip(clipId, (clip) {
      final proposedStart = clip.timelineStartSeconds + deltaSeconds;
      return clip.copyWith(
        timelineStartSeconds: _snappedTimelineStart(clip, proposedStart),
      );
    });
  }

  double _snappedTimelineStart(TimelineClip movingClip, double proposedStart) {
    const snapThresholdSeconds = 0.35;
    var bestStart = proposedStart;
    var bestDistance = snapThresholdSeconds;

    // Clip edges snap hardest so adjacent clips merge exactly (which is what
    // arms transitions); the timeline origin and playhead snap too.
    final candidates = <double>[0.0, _playheadSeconds];
    for (final clip in _clips) {
      if (clip.id == movingClip.id || clip.type != movingClip.type) {
        continue;
      }
      candidates
        ..add(clip.timelineEndSeconds)
        ..add(clip.timelineStartSeconds - movingClip.durationSeconds);
    }
    for (final candidate in candidates) {
      if (candidate < 0) {
        continue;
      }
      final distance = (candidate - proposedStart).abs();
      if (distance <= bestDistance) {
        bestDistance = distance;
        bestStart = candidate;
      }
    }
    return _resolveTrackOverlap(movingClip, bestStart);
  }

  /// Keeps clips on the same track from overlapping: when a proposed
  /// placement intersects a neighbour, the clip is pushed to abut the
  /// neighbour's nearest edge instead of stacking on top of it.
  double _resolveTrackOverlap(TimelineClip movingClip, double proposedStart) {
    final duration = movingClip.durationSeconds;
    var start = proposedStart.clamp(0.0, 3600.0).toDouble();
    for (var attempt = 0; attempt < 8; attempt++) {
      TimelineClip? blocking;
      for (final clip in _clips) {
        if (clip.id == movingClip.id ||
            clip.type != movingClip.type ||
            clip.trackIndex != movingClip.trackIndex) {
          continue;
        }
        final overlaps =
            start < clip.timelineEndSeconds - 0.001 &&
            start + duration > clip.timelineStartSeconds + 0.001;
        if (overlaps) {
          blocking = clip;
          break;
        }
      }
      if (blocking == null) {
        return start;
      }
      final blockingCenter =
          (blocking.timelineStartSeconds + blocking.timelineEndSeconds) / 2;
      final movingCenter = start + duration / 2;
      final before = blocking.timelineStartSeconds - duration;
      start = (movingCenter <= blockingCenter && before >= 0)
          ? before
          : blocking.timelineEndSeconds;
    }
    return start.clamp(0.0, 3600.0).toDouble();
  }

  void _trimClipStartOnTimeline(String clipId, double deltaSeconds) {
    _updateClip(clipId, (clip) {
      final minDuration = 0.1;
      final minDelta = math.max(
        -clip.timelineStartSeconds,
        -clip.trimStartSeconds,
      );
      final maxDelta = clip.durationSeconds - minDuration;
      final delta = deltaSeconds.clamp(minDelta, maxDelta).toDouble();
      return clip.copyWith(
        timelineStartSeconds: clip.timelineStartSeconds + delta,
        trimStartSeconds: clip.trimStartSeconds + delta,
      );
    });
  }

  void _trimClipEndOnTimeline(String clipId, double deltaSeconds) {
    final before = _clipById(clipId);
    if (before == null) {
      return;
    }
    final previousEnd = before.timelineEndSeconds;
    _updateClip(clipId, (clip) {
      final minDuration = 0.1;
      final sourceDuration = math.max(
        clip.sourceDurationSeconds ?? 3600.0,
        minDuration,
      );
      final trimEnd = (clip.trimEndSeconds + deltaSeconds)
          .clamp(clip.trimStartSeconds + minDuration, sourceDuration)
          .toDouble();
      return clip.copyWith(trimEndSeconds: trimEnd);
    });
    final after = _clipById(clipId);
    if (after != null) {
      setState(() {
        _rippleFollowersFromBoundary(
          before,
          previousEnd,
          after.timelineEndSeconds,
        );
      });
    }
  }

  void _rippleFollowersFromBoundary(
    TimelineClip anchor,
    double oldBoundary,
    double newBoundary,
  ) {
    final delta = newBoundary - oldBoundary;
    if (delta.abs() < 0.001) {
      return;
    }
    final hasAttachedFollower = _clips.any(
      (clip) =>
          clip.id != anchor.id &&
          clip.type == anchor.type &&
          clip.trackIndex == anchor.trackIndex &&
          (clip.timelineStartSeconds - oldBoundary).abs() <= 0.08,
    );
    if (!hasAttachedFollower) {
      return;
    }
    for (var i = 0; i < _clips.length; i++) {
      final clip = _clips[i];
      if (clip.id == anchor.id ||
          clip.type != anchor.type ||
          clip.trackIndex != anchor.trackIndex ||
          clip.timelineStartSeconds < oldBoundary - 0.08) {
        continue;
      }
      _clips[i] = clip.copyWith(
        timelineStartSeconds: math.max(0, clip.timelineStartSeconds + delta),
      );
    }
  }

  void _deleteClip(String clipId) {
    _recordHistory();
    setState(() {
      _clips.removeWhere((clip) => clip.id == clipId);
      _selectedClipId = _clips.isEmpty ? null : _clips.last.id;
      _status = 'Clip removed.';
      _progress = null;
    });
  }

  void _duplicateClip(String clipId) {
    final selected = _clipById(clipId);
    if (selected == null || selected.locked) {
      return;
    }

    // Place the copy flush against the original so the pair stays merged
    // (adjacent clips are what arm transitions and gapless exports).
    final duplicate = selected.copyWith(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      timelineStartSeconds: _resolveTrackOverlap(
        selected,
        selected.timelineEndSeconds,
      ),
      locked: false,
    );
    _recordHistory();
    setState(() {
      _clips.add(duplicate);
      _selectedClipId = duplicate.id;
      _playheadSeconds = duplicate.timelineStartSeconds;
      _status = 'Clip duplicated.';
      _progress = null;
    });
  }

  void _dropMediaClipOnTimeline(
    TimelineClip source,
    TimelineClipType trackType,
    int trackIndex,
    double timelineSeconds,
  ) {
    if (source.type != trackType) {
      return;
    }
    final candidate = source.copyWith(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      trackIndex: trackIndex,
      locked: false,
    );
    final dropped = _normalizeClip(
      candidate.copyWith(
        timelineStartSeconds: _snappedTimelineStart(candidate, timelineSeconds),
      ),
    );
    _recordHistory();
    setState(() {
      _clips.add(dropped);
      _selectedClipId = dropped.id;
      _playheadSeconds = dropped.timelineStartSeconds;
      _previewSeekVersion++;
      _status =
          '${dropped.name} placed at ${_seconds(dropped.timelineStartSeconds)}.';
      _progress = null;
    });
  }

  void _dropTransitionOnTimeline(
    TimelineTransition transition,
    int trackIndex,
    double timelineSeconds, {
    String? sourceClipId,
  }) {
    final candidates = _clips
        .where(
          (clip) =>
              clip.isVideo &&
              clip.trackIndex == trackIndex &&
              clip.timelineStartSeconds > 0 &&
              !clip.locked,
        )
        .toList();
    if (candidates.isEmpty) {
      return;
    }
    candidates.sort((a, b) {
      final distanceComparison = (a.timelineStartSeconds - timelineSeconds)
          .abs()
          .compareTo((b.timelineStartSeconds - timelineSeconds).abs());
      if (distanceComparison != 0) {
        return distanceComparison;
      }
      final aOnDropTrack = a.trackIndex == trackIndex;
      final bOnDropTrack = b.trackIndex == trackIndex;
      if (aOnDropTrack != bOnDropTrack) {
        return aOnDropTrack ? -1 : 1;
      }
      return a.timelineStartSeconds.compareTo(b.timelineStartSeconds);
    });
    final target = candidates.first;
    final predecessors =
        _clips
            .where(
              (clip) =>
                  clip.isVideo &&
                  clip.id != target.id &&
                  clip.timelineEndSeconds <= target.timelineStartSeconds + 0.5,
            )
            .toList()
          ..sort(
            (a, b) => (a.timelineEndSeconds - target.timelineStartSeconds)
                .abs()
                .compareTo(
                  (b.timelineEndSeconds - target.timelineStartSeconds).abs(),
                ),
          );
    final predecessor = predecessors.firstOrNull;
    final snappedStart =
        predecessor != null &&
            (predecessor.timelineEndSeconds - target.timelineStartSeconds)
                    .abs() <=
                0.5
        ? predecessor.timelineEndSeconds
        : target.timelineStartSeconds;
    _recordHistory();
    setState(() {
      for (var i = 0; i < _clips.length; i++) {
        final clip = _clips[i];
        if (clip.id == sourceClipId && clip.id != target.id) {
          _clips[i] = clip.copyWith(transition: TimelineTransition.cut);
          continue;
        }
        if (clip.id == target.id) {
          _clips[i] = _normalizeClip(
            clip.copyWith(
              timelineStartSeconds: snappedStart,
              transition: transition,
            ),
          );
        }
      }
      _selectedClipId = target.id;
      _playheadSeconds = snappedStart;
      _previewSeekVersion++;
      _status = '${_transitionName(transition)} applied to ${target.name}.';
    });
  }

  void _splitClip(String clipId) {
    final selected = _clipById(clipId);
    if (selected == null || selected.locked || !_canSplitClip(selected)) {
      return;
    }

    final splitOffset = _playheadSeconds - selected.timelineStartSeconds;
    if (splitOffset <= 0.1 || selected.durationSeconds - splitOffset <= 0.1) {
      return;
    }

    // Timeline offset -> source offset (clips play at `speed`x source rate).
    final sourceSplitOffset = splitOffset * selected.speed.clamp(0.1, 100.0);

    final first = selected.copyWith(
      trimEndSeconds: selected.trimStartSeconds + sourceSplitOffset,
    );
    // The second half starts mid-shot, so it must not inherit the original's
    // entry transition — that would replay the transition at the split point.
    final second = selected.copyWith(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      timelineStartSeconds: _playheadSeconds,
      trimStartSeconds: selected.trimStartSeconds + sourceSplitOffset,
      transition: TimelineTransition.cut,
      locked: false,
    );

    final index = _clips.indexWhere((clip) => clip.id == selected.id);
    _recordHistory();
    setState(() {
      _clips[index] = first;
      _clips.insert(index + 1, second);
      _selectedClipId = second.id;
      _status = 'Clip split.';
      _progress = null;
    });
  }

  bool _canSplitClip(TimelineClip clip) {
    return _playheadSeconds > clip.timelineStartSeconds + 0.1 &&
        _playheadSeconds < clip.timelineEndSeconds - 0.1;
  }

  void _setPlayhead(double seconds) {
    setState(() {
      _playheadSeconds = seconds.clamp(0.0, _timelineDuration).toDouble();
      _previewSeekVersion++;
    });
    if (_isPreviewPlaying) {
      _schedulePreviewSeekRestart();
    }
  }

  void _schedulePreviewSeekRestart() {
    _previewSeekRestartTimer?.cancel();
    _stopPreviewAudio();
    // Rebase the wall-clock playhead on the new position immediately.
    _startPlaybackClock();
    _previewSeekRestartTimer = Timer(const Duration(milliseconds: 90), () {
      if (!mounted || !_isPreviewPlaying) {
        return;
      }
      _startPreviewAudio();
    });
  }

  void _togglePreviewPlayback() {
    if (_isPreviewPlaying) {
      _stopPreviewPlayback();
      return;
    }

    setState(() {
      if (_playheadSeconds >= _timelineDuration - 0.05) {
        _playheadSeconds = 0;
      }
      _isPreviewPlaying = true;
    });
    _startPlaybackClock();
    _startPreviewAudio();
  }

  /// (Re)starts the playhead clock from the current playhead position.
  ///
  /// The playhead is derived from wall time, not accumulated per tick: timer
  /// ticks can be delayed under load, and audio (ffplay) runs on real time,
  /// so accumulating 1/fps per tick makes video drift behind audio.
  void _startPlaybackClock() {
    _previewPlaybackTimer?.cancel();
    final startedAt = DateTime.now();
    final startPlayhead = _playheadSeconds;
    final frameRate = _activePlaybackFrameRate();
    final frameDuration = Duration(microseconds: (1000000 / frameRate).round());
    _previewPlaybackTimer = Timer.periodic(frameDuration, (_) {
      if (!mounted) {
        return;
      }
      final elapsed =
          DateTime.now().difference(startedAt).inMicroseconds / 1000000;
      final next = startPlayhead + elapsed;
      if (next >= _timelineDuration) {
        _stopPreviewPlayback(resetToStart: true);
        return;
      }
      setState(() {
        _playheadSeconds = next;
      });
    });
  }

  double _activePlaybackFrameRate() {
    final activeVideoClips =
        _clips
            .where((clip) => clip.isVideo && clip.isActiveAt(_playheadSeconds))
            .toList()
          ..sort((a, b) {
            final trackComparison = b.trackIndex.compareTo(a.trackIndex);
            if (trackComparison != 0) {
              return trackComparison;
            }
            return b.timelineStartSeconds.compareTo(a.timelineStartSeconds);
          });
    if (activeVideoClips.isEmpty) {
      return 30;
    }
    return activeVideoClips.first.sourceFrameRate.clamp(12.0, 30.0).toDouble();
  }

  void _stopPreviewPlayback({bool resetToStart = false}) {
    _previewPlaybackTimer?.cancel();
    _previewPlaybackTimer = null;
    _previewSeekRestartTimer?.cancel();
    _previewSeekRestartTimer = null;
    _stopPreviewAudio();
    if (!mounted) {
      return;
    }
    setState(() {
      _isPreviewPlaying = false;
      if (resetToStart) {
        _playheadSeconds = 0;
      }
    });
  }

  void _startPreviewAudio() {
    _stopPreviewAudio();
    for (final clip in _clips.where(_canPreviewAudioClip)) {
      final delaySeconds = math.max(
        0.0,
        clip.timelineStartSeconds - _playheadSeconds,
      );
      void startAudio() {
        if (!_isPreviewPlaying || !mounted) {
          return;
        }
        unawaited(_startAudioProcess(clip));
      }

      if (delaySeconds <= 0) {
        startAudio();
      } else {
        _previewAudioTimers.add(
          Timer(
            Duration(milliseconds: (delaySeconds * 1000).round()),
            startAudio,
          ),
        );
      }
    }
  }

  bool _canPreviewAudioClip(TimelineClip clip) {
    return clip.enabled &&
        !clip.muted &&
        clip.volume > 0 &&
        clip.timelineEndSeconds > _playheadSeconds &&
        (clip.isAudio || clip.isVideo);
  }

  Future<void> _startAudioProcess(TimelineClip clip) async {
    final speed = clip.speed.clamp(0.1, 100.0).toDouble();
    // Timeline (wall) offset into the clip and the wall time still to play.
    final clipOffset = (_playheadSeconds - clip.timelineStartSeconds)
        .clamp(0.0, clip.durationSeconds)
        .toDouble();
    final remainingWallSeconds = clip.durationSeconds - clipOffset;
    if (remainingWallSeconds <= 0) {
      return;
    }
    final sourceOffset = clipOffset * speed;

    // The source segment ffplay reads, and the audio filters that make it
    // match the video: areverse for reverse clips, atempo for speed changes.
    // Without these the audio played forward at 1x while the video was
    // reversed/sped up — the sync bug being fixed here.
    final double readStartSeconds;
    final double readDurationSeconds;
    if (clip.reverse) {
      // Play [trimStart .. currentSourcePos] reversed, ending at trimStart.
      final currentSourcePos = (clip.trimEndSeconds - sourceOffset)
          .clamp(clip.trimStartSeconds, clip.trimEndSeconds)
          .toDouble();
      readStartSeconds = clip.trimStartSeconds;
      readDurationSeconds = currentSourcePos - clip.trimStartSeconds;
    } else {
      readStartSeconds = (clip.trimStartSeconds + sourceOffset)
          .clamp(clip.trimStartSeconds, clip.trimEndSeconds)
          .toDouble();
      readDurationSeconds = clip.trimEndSeconds - readStartSeconds;
    }
    if (readDurationSeconds <= 0) {
      return;
    }

    final audioFilters = <String>[
      if (clip.reverse) 'areverse',
      ...FilterSnippets.audioTempo(speed),
    ];

    // ffplay runs on real time, so the cutoff is measured in wall time.
    final cutoffDeadline = DateTime.now().add(
      Duration(microseconds: (remainingWallSeconds * 1000000).round()),
    );

    try {
      final process = await Process.start(FfmpegExecutables.ffplay, <String>[
        '-nodisp',
        '-autoexit',
        '-loglevel',
        'quiet',
        '-ss',
        _ffmpegNumber(readStartSeconds),
        '-t',
        _ffmpegNumber(readDurationSeconds),
        if (audioFilters.isNotEmpty) ...['-af', audioFilters.join(',')],
        '-volume',
        '${(clip.volume.clamp(0.0, 2.0) * 100).round()}',
        clip.path,
      ]);
      if (!_isPreviewPlaying || !mounted) {
        process.kill();
        return;
      }
      _previewAudioProcesses.add(process);
      final cutoffDelay = cutoffDeadline.difference(DateTime.now());
      if (cutoffDelay <= Duration.zero) {
        process.kill();
        _previewAudioProcesses.remove(process);
        return;
      }

      Timer? cutoffTimer;
      cutoffTimer = Timer(cutoffDelay, () {
        process.kill();
        _previewAudioProcesses.remove(process);
        _previewAudioTimers.remove(cutoffTimer);
      });
      _previewAudioTimers.add(cutoffTimer);
      unawaited(
        process.exitCode.then((_) {
          cutoffTimer?.cancel();
          _previewAudioTimers.remove(cutoffTimer);
          _previewAudioProcesses.remove(process);
        }),
      );
    } catch (_) {
      return;
    }
  }

  void _stopPreviewAudio() {
    for (final timer in _previewAudioTimers) {
      timer.cancel();
    }
    _previewAudioTimers.clear();
    for (final process in _previewAudioProcesses) {
      process.kill();
    }
    _previewAudioProcesses.clear();
  }

  ManualEditProject _buildProject() {
    return ManualEditProject(
      outputPath: _cleanPath(_outputController.text),
      width: _canvasPreset.width,
      height: _canvasPreset.height,
      frameRate: 60,
      backgroundHexColor: '101418',
      blurredBackgroundEnabled: _blurredBackgroundEnabled,
      clips: List.unmodifiable(_clips),
    );
  }

  void _recordHistory() {
    _undoStack.add(_buildProject());
    if (_undoStack.length > 80) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  void _restoreProject(ManualEditProject project, String status) {
    _outputController.text = project.outputPath;
    _canvasPreset = _canvasPresetFor(project.width, project.height);
    _blurredBackgroundEnabled = project.blurredBackgroundEnabled;
    _clips
      ..clear()
      ..addAll(project.clips);
    _selectedClipId = _clips.any((clip) => clip.id == _selectedClipId)
        ? _selectedClipId
        : _clips.lastOrNull?.id;
    _playheadSeconds = _playheadSeconds
        .clamp(0.0, _timelineDuration)
        .toDouble();
    _previewSeekVersion++;
    _progress = null;
    _status = status;
  }

  _ManualCanvasPreset _canvasPresetFor(int width, int height) {
    for (final preset in _ManualCanvasPreset.values) {
      if (preset.width == width && preset.height == height) {
        return preset;
      }
    }
    return _ManualCanvasPreset.vertical;
  }

  void _undo() {
    if (!_canUndo) {
      return;
    }
    final previous = _undoStack.removeLast();
    _redoStack.add(_buildProject());
    _stopPreviewPlayback();
    setState(() {
      _restoreProject(previous, 'Undo applied.');
    });
  }

  void _redo() {
    if (!_canRedo) {
      return;
    }
    final next = _redoStack.removeLast();
    _undoStack.add(_buildProject());
    _stopPreviewPlayback();
    setState(() {
      _restoreProject(next, 'Redo applied.');
    });
  }

  Future<void> _saveProject() async {
    if (!Platform.isWindows || _isRendering) {
      return;
    }
    try {
      final selectedPath = await _filePickerChannel.invokeMethod<String>(
        'saveProject',
      );
      if (!mounted || selectedPath == null || selectedPath.trim().isEmpty) {
        return;
      }
      await _projectStore.save(_buildProject(), _cleanPath(selectedPath));
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Project saved.';
        _progress = null;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Could not save project: $error';
        _progress = null;
      });
    }
  }

  Future<void> _openProject() async {
    if (!Platform.isWindows || _isRendering) {
      return;
    }
    try {
      final selectedPath = await _filePickerChannel.invokeMethod<String>(
        'pickProject',
      );
      if (!mounted || selectedPath == null || selectedPath.trim().isEmpty) {
        return;
      }
      final project = await _projectStore.open(_cleanPath(selectedPath));
      if (!mounted) {
        return;
      }
      _recordHistory();
      _stopPreviewPlayback();
      setState(() {
        _restoreProject(project, 'Project opened.');
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Could not open project: $error';
        _progress = null;
      });
    }
  }

  Future<void> _exportTimeline() async {
    final outputPath = _cleanPath(_outputController.text);
    if (_outputController.text != outputPath) {
      _outputController.text = outputPath;
    }

    final job = ManualRenderJob(project: _buildProject());
    await _renderSubscription?.cancel();
    setState(() {
      _isRendering = true;
      _progress = 0;
      _status = 'Timeline queued.';
    });

    _renderSubscription = _exportUseCase(job).listen(
      (progress) {
        setState(() {
          _progress = progress.fraction;
          _status = progress.message;
          _isRendering = !progress.isTerminal;
        });
        if (progress.status == RenderJobStatus.completed &&
            progress.outputPath != null) {
          unawaited(
            DesktopNotifier.show(
              title: 'Export complete',
              body:
                  '${p.basename(progress.outputPath!)} is ready to preview '
                  'and publish.',
            ),
          );
          _offerPublish(progress.outputPath!);
        } else if (progress.status == RenderJobStatus.failed) {
          unawaited(
            DesktopNotifier.show(
              title: 'Export failed',
              body: progress.message,
            ),
          );
        }
      },
      onError: (Object error) {
        setState(() {
          _status = '$error';
          _isRendering = false;
          _progress = null;
        });
        unawaited(
          DesktopNotifier.show(title: 'Export failed', body: '$error'),
        );
      },
      onDone: () {
        setState(() {
          _isRendering = false;
        });
      },
    );
  }

  void _offerPublish(String videoPath) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Export complete.'),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'Preview & publish',
            onPressed: () => _openPublishSheet(videoPath),
          ),
        ),
      );
  }

  void _openPublishSheet(String videoPath) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF080808),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RenderedClipPlayer(videoPath: videoPath),
                  const SizedBox(height: 16),
                  PublishPanel(
                    videoPath: videoPath,
                    defaultTitle: p.basenameWithoutExtension(videoPath),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _playbackFocusNode,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is! KeyDownEvent || _keyboardFocusIsTextInput()) {
          return;
        }
        final isModifierPressed =
            HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed;
        if (isModifierPressed && event.logicalKey == LogicalKeyboardKey.keyZ) {
          _undo();
          return;
        }
        if (isModifierPressed && event.logicalKey == LogicalKeyboardKey.keyY) {
          _redo();
          return;
        }
        if (event.logicalKey == LogicalKeyboardKey.space) {
          _togglePreviewPlayback();
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1180;
          final toolbar = _EditorToolbar(
            editorView: _editorView,
            canvasPreset: _canvasPreset,
            outputController: _outputController,
            isRendering: _isRendering,
            canExport: _canExport,
            desktopRendererAvailable: widget.desktopRendererAvailable,
            progress: _progress,
            status: _status,
            blurredBackgroundEnabled: _blurredBackgroundEnabled,
            canUndo: _canUndo,
            canRedo: _canRedo,
            canSaveProject: !_isRendering && _clips.isNotEmpty,
            onCanvasPresetChanged: (preset) {
              if (preset == _canvasPreset) {
                return;
              }
              _recordHistory();
              setState(() {
                _canvasPreset = preset;
              });
            },
            onBlurredBackgroundChanged: (enabled) {
              if (enabled == _blurredBackgroundEnabled) {
                return;
              }
              _recordHistory();
              setState(() {
                _blurredBackgroundEnabled = enabled;
              });
            },
            onEditorViewChanged: (view) {
              if (view == _EditorView.edit) {
                _stopPreviewPlayback();
              }
              setState(() {
                _editorView = view;
              });
            },
            onExport: _exportTimeline,
            onOpenProject: _openProject,
            onSaveProject: _saveProject,
            onUndo: _undo,
            onRedo: _redo,
          );

          if (wide) {
            final workspaceHeight = math.max(
              _editorView == _EditorView.edit ? 720.0 : 760.0,
              constraints.maxHeight - 180,
            );
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  toolbar,
                  const SizedBox(height: 12),
                  SizedBox(
                    height: workspaceHeight,
                    child: _editorView == _EditorView.edit
                        ? _EditWorkspace(
                            clips: _clips,
                            selectedClipId: _selectedClipId,
                            selectedClip: _selectedClip,
                            canvasPreset: _canvasPreset,
                            blurredBackgroundEnabled: _blurredBackgroundEnabled,
                            canChooseMedia: _canChooseMedia,
                            playheadSeconds: _playheadSeconds,
                            previewSeekVersion: _previewSeekVersion,
                            timelineDuration: _timelineDuration,
                            isPlaying: _isPreviewPlaying,
                            onAddVideo: () => _addClip(TimelineClipType.video),
                            onAddAudio: () => _addClip(TimelineClipType.audio),
                            onSelectClip: _selectClip,
                            onMoveClipOnCanvas: _moveClipOnCanvas,
                            onMoveClipOnTimeline: _moveClipOnTimeline,
                            onTrimClipStart: _trimClipStartOnTimeline,
                            onTrimClipEnd: _trimClipEndOnTimeline,
                            onPlayheadChanged: _setPlayhead,
                            onTogglePlayback: _togglePreviewPlayback,
                            onClipChanged: (clip) {
                              _updateClip(clip.id, (_) => clip);
                            },
                            onDuplicateClip: _duplicateClip,
                            onSplitClip: _splitClip,
                            onDeleteClip: _deleteClip,
                            onDropMediaClip: _dropMediaClipOnTimeline,
                            onDropTransition: _dropTransitionOnTimeline,
                          )
                        : _PreviewWorkspace(
                            canvasPreset: _canvasPreset,
                            blurredBackgroundEnabled: _blurredBackgroundEnabled,
                            clips: _clips,
                            selectedClipId: _selectedClipId,
                            playheadSeconds: _playheadSeconds,
                            previewSeekVersion: _previewSeekVersion,
                            timelineDuration: _timelineDuration,
                            isPlaying: _isPreviewPlaying,
                            onSelectClip: _selectClip,
                            onPlayheadChanged: _setPlayhead,
                            onTogglePlayback: _togglePreviewPlayback,
                          ),
                  ),
                ],
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                toolbar,
                const SizedBox(height: 12),
                if (_editorView == _EditorView.edit)
                  SizedBox(
                    height: 1780,
                    child: _EditWorkspace(
                      clips: _clips,
                      selectedClipId: _selectedClipId,
                      selectedClip: _selectedClip,
                      canvasPreset: _canvasPreset,
                      blurredBackgroundEnabled: _blurredBackgroundEnabled,
                      canChooseMedia: _canChooseMedia,
                      playheadSeconds: _playheadSeconds,
                      previewSeekVersion: _previewSeekVersion,
                      timelineDuration: _timelineDuration,
                      isPlaying: _isPreviewPlaying,
                      onAddVideo: () => _addClip(TimelineClipType.video),
                      onAddAudio: () => _addClip(TimelineClipType.audio),
                      onSelectClip: _selectClip,
                      onMoveClipOnCanvas: _moveClipOnCanvas,
                      onMoveClipOnTimeline: _moveClipOnTimeline,
                      onTrimClipStart: _trimClipStartOnTimeline,
                      onTrimClipEnd: _trimClipEndOnTimeline,
                      onPlayheadChanged: _setPlayhead,
                      onTogglePlayback: _togglePreviewPlayback,
                      onClipChanged: (clip) {
                        _updateClip(clip.id, (_) => clip);
                      },
                      onDuplicateClip: _duplicateClip,
                      onSplitClip: _splitClip,
                      onDeleteClip: _deleteClip,
                      onDropMediaClip: _dropMediaClipOnTimeline,
                      onDropTransition: _dropTransitionOnTimeline,
                      stacked: true,
                    ),
                  )
                else
                  SizedBox(
                    height: 720,
                    child: _PreviewWorkspace(
                      canvasPreset: _canvasPreset,
                      blurredBackgroundEnabled: _blurredBackgroundEnabled,
                      clips: _clips,
                      selectedClipId: _selectedClipId,
                      playheadSeconds: _playheadSeconds,
                      previewSeekVersion: _previewSeekVersion,
                      timelineDuration: _timelineDuration,
                      isPlaying: _isPreviewPlaying,
                      onSelectClip: _selectClip,
                      onPlayheadChanged: _setPlayhead,
                      onTogglePlayback: _togglePreviewPlayback,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  bool _keyboardFocusIsTextInput() {
    final focusedWidget = FocusManager.instance.primaryFocus?.context?.widget;
    return focusedWidget is EditableText;
  }
}

class _EditWorkspace extends StatefulWidget {
  const _EditWorkspace({
    required this.clips,
    required this.selectedClipId,
    required this.selectedClip,
    required this.canvasPreset,
    required this.blurredBackgroundEnabled,
    required this.canChooseMedia,
    required this.playheadSeconds,
    required this.previewSeekVersion,
    required this.timelineDuration,
    required this.isPlaying,
    required this.onAddVideo,
    required this.onAddAudio,
    required this.onSelectClip,
    required this.onMoveClipOnCanvas,
    required this.onMoveClipOnTimeline,
    required this.onTrimClipStart,
    required this.onTrimClipEnd,
    required this.onPlayheadChanged,
    required this.onTogglePlayback,
    required this.onClipChanged,
    required this.onDuplicateClip,
    required this.onSplitClip,
    required this.onDeleteClip,
    required this.onDropMediaClip,
    required this.onDropTransition,
    this.stacked = false,
  });

  final List<TimelineClip> clips;
  final String? selectedClipId;
  final TimelineClip? selectedClip;
  final _ManualCanvasPreset canvasPreset;
  final bool blurredBackgroundEnabled;
  final bool canChooseMedia;
  final double playheadSeconds;
  final int previewSeekVersion;
  final double timelineDuration;
  final bool isPlaying;
  final VoidCallback onAddVideo;
  final VoidCallback onAddAudio;
  final ValueChanged<String> onSelectClip;
  final void Function(String clipId, Offset normalizedDelta) onMoveClipOnCanvas;
  final void Function(String clipId, double deltaSeconds) onMoveClipOnTimeline;
  final void Function(String clipId, double deltaSeconds) onTrimClipStart;
  final void Function(String clipId, double deltaSeconds) onTrimClipEnd;
  final ValueChanged<double> onPlayheadChanged;
  final VoidCallback onTogglePlayback;
  final ValueChanged<TimelineClip> onClipChanged;
  final ValueChanged<String> onDuplicateClip;
  final ValueChanged<String> onSplitClip;
  final ValueChanged<String> onDeleteClip;
  final void Function(
    TimelineClip clip,
    TimelineClipType trackType,
    int trackIndex,
    double timelineSeconds,
  )
  onDropMediaClip;
  final void Function(
    TimelineTransition transition,
    int trackIndex,
    double timelineSeconds, {
    String? sourceClipId,
  })
  onDropTransition;
  final bool stacked;

  @override
  State<_EditWorkspace> createState() => _EditWorkspaceState();
}

class _EditWorkspaceState extends State<_EditWorkspace> {
  double _mediaWidth = 270;
  double _inspectorWidth = 320;
  double _timelineHeight = 250;

  @override
  Widget build(BuildContext context) {
    final preview = _PreviewCanvasPanel(
      canvasPreset: widget.canvasPreset,
      blurredBackgroundEnabled: widget.blurredBackgroundEnabled,
      clips: widget.clips,
      selectedClipId: widget.selectedClipId,
      playheadSeconds: widget.playheadSeconds,
      previewSeekVersion: widget.previewSeekVersion,
      enableLiveFrames: true,
      isPlaying: widget.isPlaying,
      onSelectClip: widget.onSelectClip,
      onMoveClip: widget.onMoveClipOnCanvas,
    );
    final playback = _PlaybackControls(
      isPlaying: widget.isPlaying,
      playheadSeconds: widget.playheadSeconds,
      timelineDuration: widget.timelineDuration,
      onTogglePlayback: widget.onTogglePlayback,
      onPlayheadChanged: widget.onPlayheadChanged,
    );
    final timeline = _TimelinePanel(
      clips: widget.clips,
      selectedClipId: widget.selectedClipId,
      playheadSeconds: widget.playheadSeconds,
      timelineDuration: widget.timelineDuration,
      onPlayheadChanged: widget.onPlayheadChanged,
      onSelectClip: widget.onSelectClip,
      onMoveClip: widget.onMoveClipOnTimeline,
      onTrimClipStart: widget.onTrimClipStart,
      onTrimClipEnd: widget.onTrimClipEnd,
      onDuplicateClip: widget.onDuplicateClip,
      onSplitClip: widget.onSplitClip,
      onDeleteClip: widget.onDeleteClip,
      onDropMediaClip: widget.onDropMediaClip,
      onDropTransition: widget.onDropTransition,
    );
    final media = _MediaBinPanel(
      clips: widget.clips,
      selectedClipId: widget.selectedClipId,
      canChooseMedia: widget.canChooseMedia,
      onAddVideo: widget.onAddVideo,
      onAddAudio: widget.onAddAudio,
      onSelectClip: widget.onSelectClip,
    );
    final inspector = widget.selectedClip?.isVideo ?? false
        ? _AdvancedVideoInspectorPanel(
            clip: widget.selectedClip!,
            timelineDuration: widget.timelineDuration,
            onClipChanged: widget.onClipChanged,
          )
        : _InspectorPanel(
            clip: widget.selectedClip,
            timelineDuration: widget.timelineDuration,
            onClipChanged: widget.onClipChanged,
          );

    if (widget.stacked) {
      return Column(
        children: [
          SizedBox(height: 420, child: preview),
          const SizedBox(height: 12),
          playback,
          const SizedBox(height: 12),
          SizedBox(height: 270, child: timeline),
          const SizedBox(height: 12),
          SizedBox(height: 360, child: media),
          const SizedBox(height: 12),
          SizedBox(height: 520, child: inspector),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const minMediaWidth = 180.0;
        const minInspectorWidth = 240.0;
        const minCenterWidth = 420.0;
        const handleSpace = 20.0;
        final maxMediaWidth = math.max(
          minMediaWidth,
          constraints.maxWidth -
              minInspectorWidth -
              minCenterWidth -
              handleSpace,
        );
        final mediaWidth = _mediaWidth
            .clamp(minMediaWidth, maxMediaWidth)
            .toDouble();
        final maxInspectorWidth = math.max(
          minInspectorWidth,
          constraints.maxWidth - mediaWidth - minCenterWidth - handleSpace,
        );
        final inspectorWidth = _inspectorWidth
            .clamp(minInspectorWidth, maxInspectorWidth)
            .toDouble();

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: mediaWidth, child: media),
            _VerticalResizeHandle(
              onDrag: (delta) {
                setState(() {
                  _mediaWidth += delta.dx;
                });
              },
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, centerConstraints) {
                  final maxTimelineHeight = math.max(
                    150.0,
                    centerConstraints.maxHeight - 250,
                  );
                  final timelineHeight = _timelineHeight
                      .clamp(150.0, maxTimelineHeight)
                      .toDouble();

                  return Column(
                    children: [
                      Expanded(child: preview),
                      _HorizontalResizeHandle(
                        onDrag: (delta) {
                          setState(() {
                            _timelineHeight -= delta.dy;
                          });
                        },
                      ),
                      playback,
                      const SizedBox(height: 10),
                      SizedBox(height: timelineHeight, child: timeline),
                    ],
                  );
                },
              ),
            ),
            _VerticalResizeHandle(
              onDrag: (delta) {
                setState(() {
                  _inspectorWidth -= delta.dx;
                });
              },
            ),
            SizedBox(width: inspectorWidth, child: inspector),
          ],
        );
      },
    );
  }
}

class _VerticalResizeHandle extends StatelessWidget {
  const _VerticalResizeHandle({required this.onDrag});

  final ValueChanged<Offset> onDrag;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) => onDrag(details.delta),
        child: SizedBox(
          width: 10,
          child: Center(
            child: Container(
              width: 2,
              decoration: BoxDecoration(
                color: const Color(0xFF343434),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HorizontalResizeHandle extends StatelessWidget {
  const _HorizontalResizeHandle({required this.onDrag});

  final ValueChanged<Offset> onDrag;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) => onDrag(details.delta),
        child: SizedBox(
          height: 10,
          child: Center(
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                color: const Color(0xFF343434),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewWorkspace extends StatelessWidget {
  const _PreviewWorkspace({
    required this.canvasPreset,
    required this.blurredBackgroundEnabled,
    required this.clips,
    required this.selectedClipId,
    required this.playheadSeconds,
    required this.previewSeekVersion,
    required this.timelineDuration,
    required this.isPlaying,
    required this.onSelectClip,
    required this.onPlayheadChanged,
    required this.onTogglePlayback,
  });

  final _ManualCanvasPreset canvasPreset;
  final bool blurredBackgroundEnabled;
  final List<TimelineClip> clips;
  final String? selectedClipId;
  final double playheadSeconds;
  final int previewSeekVersion;
  final double timelineDuration;
  final bool isPlaying;
  final ValueChanged<String> onSelectClip;
  final ValueChanged<double> onPlayheadChanged;
  final VoidCallback onTogglePlayback;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _PreviewCanvasPanel(
            canvasPreset: canvasPreset,
            blurredBackgroundEnabled: blurredBackgroundEnabled,
            clips: clips,
            selectedClipId: selectedClipId,
            playheadSeconds: playheadSeconds,
            previewSeekVersion: previewSeekVersion,
            allowEditing: false,
            enableLiveFrames: true,
            isPlaying: isPlaying,
            onSelectClip: onSelectClip,
            onMoveClip: (_, _) {},
          ),
        ),
        const SizedBox(height: 12),
        _PlaybackControls(
          isPlaying: isPlaying,
          playheadSeconds: playheadSeconds,
          timelineDuration: timelineDuration,
          onTogglePlayback: onTogglePlayback,
          onPlayheadChanged: onPlayheadChanged,
        ),
      ],
    );
  }
}

class _PlaybackControls extends StatelessWidget {
  const _PlaybackControls({
    required this.isPlaying,
    required this.playheadSeconds,
    required this.timelineDuration,
    required this.onTogglePlayback,
    required this.onPlayheadChanged,
  });

  final bool isPlaying;
  final double playheadSeconds;
  final double timelineDuration;
  final VoidCallback onTogglePlayback;
  final ValueChanged<double> onPlayheadChanged;

  @override
  Widget build(BuildContext context) {
    return _EditorPanel(
      title: 'Playback',
      expandChild: false,
      actions: [
        _InfoChip(icon: Icons.timer_outlined, label: _seconds(playheadSeconds)),
      ],
      child: Row(
        children: [
          IconButton.filledTonal(
            onPressed: onTogglePlayback,
            tooltip: isPlaying ? 'Pause video' : 'Play video',
            icon: Icon(
              isPlaying ? Icons.pause_outlined : Icons.play_arrow_outlined,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Slider(
              value: playheadSeconds.clamp(0.0, timelineDuration).toDouble(),
              min: 0,
              max: timelineDuration,
              divisions: math.max(1, (timelineDuration * 10).round()),
              onChanged: onPlayheadChanged,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _seconds(timelineDuration),
            style: const TextStyle(
              color: Color(0xFFD0D0D0),
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _EditorToolbar extends StatelessWidget {
  const _EditorToolbar({
    required this.editorView,
    required this.canvasPreset,
    required this.outputController,
    required this.isRendering,
    required this.canExport,
    required this.desktopRendererAvailable,
    required this.progress,
    required this.status,
    required this.blurredBackgroundEnabled,
    required this.canUndo,
    required this.canRedo,
    required this.canSaveProject,
    required this.onCanvasPresetChanged,
    required this.onBlurredBackgroundChanged,
    required this.onEditorViewChanged,
    required this.onExport,
    required this.onOpenProject,
    required this.onSaveProject,
    required this.onUndo,
    required this.onRedo,
  });

  final _EditorView editorView;
  final _ManualCanvasPreset canvasPreset;
  final TextEditingController outputController;
  final bool isRendering;
  final bool canExport;
  final bool desktopRendererAvailable;
  final double? progress;
  final String status;
  final bool blurredBackgroundEnabled;
  final bool canUndo;
  final bool canRedo;
  final bool canSaveProject;
  final ValueChanged<_ManualCanvasPreset> onCanvasPresetChanged;
  final ValueChanged<bool> onBlurredBackgroundChanged;
  final ValueChanged<_EditorView> onEditorViewChanged;
  final VoidCallback onExport;
  final VoidCallback onOpenProject;
  final VoidCallback onSaveProject;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

  @override
  Widget build(BuildContext context) {
    return _EditorPanel(
      title: 'Custom Editor',
      expandChild: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 860;
          final viewSelector = SegmentedButton<_EditorView>(
            showSelectedIcon: false,
            segments: [
              for (final view in _EditorView.values)
                ButtonSegment(
                  value: view,
                  icon: Icon(view.icon),
                  label: Text(view.label),
                ),
            ],
            selected: {editorView},
            onSelectionChanged: isRendering
                ? null
                : (selection) => onEditorViewChanged(selection.first),
          );
          final canvasSelector = SegmentedButton<_ManualCanvasPreset>(
            segments: [
              for (final preset in _ManualCanvasPreset.values)
                ButtonSegment(
                  value: preset,
                  icon: Icon(preset.icon),
                  label: Text(preset.label),
                ),
            ],
            selected: {canvasPreset},
            onSelectionChanged: isRendering
                ? null
                : (selection) => onCanvasPresetChanged(selection.first),
          );
          final outputField = TextField(
            controller: outputController,
            enabled: !isRendering,
            decoration: const InputDecoration(
              labelText: 'Output mp4 path',
              prefixIcon: Icon(Icons.save_alt_outlined),
            ),
          );
          final exportButton = FilledButton.icon(
            onPressed: canExport ? onExport : null,
            icon: isRendering
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share_outlined),
            label: Text(isRendering ? 'Exporting' : 'Export Timeline'),
          );
          final blurToggle = FilterChip(
            avatar: const Icon(Icons.blur_on_outlined, size: 18),
            label: const Text('Blur BG'),
            selected: blurredBackgroundEnabled,
            onSelected: isRendering ? null : onBlurredBackgroundChanged,
          );
          final projectButtons = Wrap(
            spacing: 8,
            children: [
              IconButton.filledTonal(
                onPressed: isRendering ? null : onOpenProject,
                tooltip: 'Open project',
                icon: const Icon(Icons.folder_open_outlined),
              ),
              IconButton.filledTonal(
                onPressed: canSaveProject ? onSaveProject : null,
                tooltip: 'Save project',
                icon: const Icon(Icons.save_outlined),
              ),
              IconButton.filledTonal(
                onPressed: canUndo ? onUndo : null,
                tooltip: 'Undo',
                icon: const Icon(Icons.undo_outlined),
              ),
              IconButton.filledTonal(
                onPressed: canRedo ? onRedo : null,
                tooltip: 'Redo',
                icon: const Icon(Icons.redo_outlined),
              ),
            ],
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (compact) ...[
                viewSelector,
                const SizedBox(height: 12),
                canvasSelector,
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [blurToggle, projectButtons],
                  ),
                ),
                const SizedBox(height: 12),
                outputField,
                const SizedBox(height: 12),
                exportButton,
              ] else
                Row(
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 260),
                      child: viewSelector,
                    ),
                    const SizedBox(width: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: canvasSelector,
                    ),
                    const SizedBox(width: 12),
                    blurToggle,
                    const SizedBox(width: 12),
                    projectButtons,
                    const SizedBox(width: 12),
                    Expanded(child: outputField),
                    const SizedBox(width: 12),
                    exportButton,
                  ],
                ),
              if (!desktopRendererAvailable) ...[
                const SizedBox(height: 12),
                const _InlineNotice(
                  icon: Icons.desktop_windows_outlined,
                  text: 'Desktop FFmpeg rendering is wired first.',
                ),
              ],
              const SizedBox(height: 12),
              if (isRendering || progress != null) ...[
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 8),
              ],
              Text(
                status,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFD0D0D0),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MediaBinPanel extends StatelessWidget {
  const _MediaBinPanel({
    required this.clips,
    required this.selectedClipId,
    required this.canChooseMedia,
    required this.onAddVideo,
    required this.onAddAudio,
    required this.onSelectClip,
  });

  final List<TimelineClip> clips;
  final String? selectedClipId;
  final bool canChooseMedia;
  final VoidCallback onAddVideo;
  final VoidCallback onAddAudio;
  final ValueChanged<String> onSelectClip;

  @override
  Widget build(BuildContext context) {
    final mediaByPath = <String, TimelineClip>{};
    for (final clip in clips) {
      mediaByPath.putIfAbsent(clip.path, () => clip);
    }
    final mediaClips = mediaByPath.values.toList();
    final selectedPath = clips
        .where((clip) => clip.id == selectedClipId)
        .firstOrNull
        ?.path;
    return _EditorPanel(
      title: 'Library',
      actions: [
        IconButton.filledTonal(
          onPressed: canChooseMedia ? onAddVideo : null,
          tooltip: 'Add video',
          icon: const Icon(Icons.video_file_outlined),
        ),
        IconButton.filledTonal(
          onPressed: canChooseMedia ? onAddAudio : null,
          tooltip: 'Add audio',
          icon: const Icon(Icons.audio_file_outlined),
        ),
      ],
      child: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(icon: Icon(Icons.perm_media_outlined), text: 'Media'),
                Tab(icon: Icon(Icons.auto_awesome_motion), text: 'Transitions'),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                children: [
                  mediaClips.isEmpty
                      ? const Center(
                          child: Text(
                            'No clips',
                            style: TextStyle(color: Color(0xFF9A9A9A)),
                          ),
                        )
                      : ListView.separated(
                          itemCount: mediaClips.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final clip = mediaClips[index];
                            final selected = clip.path == selectedPath;
                            return Draggable<_TimelineDragPayload>(
                              data: _MediaClipDragPayload(clip),
                              dragAnchorStrategy: pointerDragAnchorStrategy,
                              feedback: Material(
                                color: Colors.transparent,
                                child: SizedBox(
                                  width: 230,
                                  child: _MediaBinTile(
                                    clip: clip,
                                    selected: true,
                                    onTap: () {},
                                  ),
                                ),
                              ),
                              childWhenDragging: Opacity(
                                opacity: 0.35,
                                child: _MediaBinTile(
                                  clip: clip,
                                  selected: selected,
                                  onTap: () => onSelectClip(clip.id),
                                ),
                              ),
                              child: _MediaBinTile(
                                clip: clip,
                                selected: selected,
                                onTap: () => onSelectClip(clip.id),
                              ),
                            );
                          },
                        ),
                  ListView.separated(
                    itemCount: TimelineTransition.values.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final transition = TimelineTransition.values[index];
                      return Draggable<_TimelineDragPayload>(
                        data: _TransitionDragPayload(transition),
                        dragAnchorStrategy: pointerDragAnchorStrategy,
                        feedback: Material(
                          color: Colors.transparent,
                          child: SizedBox(
                            width: 220,
                            child: _TransitionLibraryTile(
                              transition: transition,
                              active: true,
                            ),
                          ),
                        ),
                        childWhenDragging: Opacity(
                          opacity: 0.35,
                          child: _TransitionLibraryTile(transition: transition),
                        ),
                        child: _TransitionLibraryTile(transition: transition),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransitionLibraryTile extends StatelessWidget {
  const _TransitionLibraryTile({required this.transition, this.active = false});

  final TimelineTransition transition;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      color: active ? const Color(0xFF303030) : const Color(0xFF151515),
      child: Row(
        children: [
          Icon(_transitionIconData(transition), color: const Color(0xFFB8B8B8)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _transitionName(transition),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const Icon(
            Icons.drag_indicator_outlined,
            size: 18,
            color: Color(0xFF777777),
          ),
        ],
      ),
    );
  }
}

class _MediaBinTile extends StatelessWidget {
  const _MediaBinTile({
    required this.clip,
    required this.selected,
    required this.onTap,
  });

  final TimelineClip clip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = clip.isVideo
        ? const Color(0xFF6F97A5)
        : const Color(0xFF668C72);
    return Material(
      color: selected ? const Color(0xFF262626) : const Color(0xFF151515),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Icon(
                clip.isVideo
                    ? Icons.movie_creation_outlined
                    : Icons.graphic_eq_outlined,
                color: color,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clip.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_seconds(clip.timelineStartSeconds)} - '
                      '${_seconds(clip.timelineEndSeconds)}',
                      style: const TextStyle(
                        color: Color(0xFF9A9A9A),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewCanvasPanel extends StatelessWidget {
  const _PreviewCanvasPanel({
    required this.canvasPreset,
    required this.blurredBackgroundEnabled,
    required this.clips,
    required this.selectedClipId,
    required this.playheadSeconds,
    required this.previewSeekVersion,
    required this.onSelectClip,
    required this.onMoveClip,
    this.allowEditing = true,
    this.enableLiveFrames = false,
    this.isPlaying = false,
  });

  final _ManualCanvasPreset canvasPreset;
  final bool blurredBackgroundEnabled;
  final List<TimelineClip> clips;
  final String? selectedClipId;
  final double playheadSeconds;
  final int previewSeekVersion;
  final ValueChanged<String> onSelectClip;
  final void Function(String clipId, Offset normalizedDelta) onMoveClip;
  final bool allowEditing;
  final bool enableLiveFrames;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    final visibleVideoClips =
        clips
            .where(
              (clip) =>
                  clip.isVideo &&
                  _isVideoClipVisibleAt(clip, clips, playheadSeconds),
            )
            .toList()
          ..sort((a, b) {
            final trackComparison = a.trackIndex.compareTo(b.trackIndex);
            if (trackComparison != 0) {
              return trackComparison;
            }
            return a.timelineStartSeconds.compareTo(b.timelineStartSeconds);
          });
    final previewVideoClips =
        clips
            .where(
              (clip) =>
                  clip.isVideo &&
                  (_isVideoClipVisibleAt(clip, clips, playheadSeconds) ||
                      (isPlaying &&
                          clip.enabled &&
                          clip.timelineStartSeconds > playheadSeconds &&
                          clip.timelineStartSeconds - playheadSeconds <= 2)),
            )
            .toList()
          ..sort((a, b) {
            final trackComparison = a.trackIndex.compareTo(b.trackIndex);
            if (trackComparison != 0) {
              return trackComparison;
            }
            return a.timelineStartSeconds.compareTo(b.timelineStartSeconds);
          });
    _prioritizeActiveTransition(visibleVideoClips, playheadSeconds);
    _prioritizeActiveTransition(previewVideoClips, playheadSeconds);

    return _EditorPanel(
      title: 'Preview',
      actions: [
        _InfoChip(
          icon: canvasPreset.icon,
          label: '${canvasPreset.width}x${canvasPreset.height}',
        ),
        _InfoChip(icon: Icons.timer_outlined, label: _seconds(playheadSeconds)),
      ],
      child: Center(
        child: AspectRatio(
          aspectRatio: canvasPreset.width / canvasPreset.height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: DecoratedBox(
              decoration: const BoxDecoration(color: Color(0xFF050505)),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (visibleVideoClips.isEmpty) {
                    return const Center(
                      child: Icon(
                        Icons.smart_display_outlined,
                        color: Color(0xFF5C5C5C),
                        size: 58,
                      ),
                    );
                  }

                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      if (blurredBackgroundEnabled)
                        _BlurredPreviewBackground(
                          clip: visibleVideoClips.last,
                          playheadSeconds: playheadSeconds,
                          previewSeekVersion: previewSeekVersion,
                          enabled: enableLiveFrames,
                          isPlaying: isPlaying,
                        ),
                      for (final clip in previewVideoClips)
                        _PreviewVideoLayer(
                          key: ValueKey(clip.id),
                          clip: clip,
                          selected: clip.id == selectedClipId,
                          allowEditing: allowEditing,
                          enableLiveFrames: enableLiveFrames,
                          isPlaying: isPlaying,
                          playheadSeconds: playheadSeconds,
                          previewSeekVersion: previewSeekVersion,
                          canvasSize: Size(
                            constraints.maxWidth,
                            constraints.maxHeight,
                          ),
                          onSelect: () => onSelectClip(clip.id),
                          onMove: (delta) => onMoveClip(clip.id, delta),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewVideoLayer extends StatelessWidget {
  const _PreviewVideoLayer({
    super.key,
    required this.clip,
    required this.selected,
    required this.allowEditing,
    required this.enableLiveFrames,
    required this.isPlaying,
    required this.playheadSeconds,
    required this.previewSeekVersion,
    required this.canvasSize,
    required this.onSelect,
    required this.onMove,
  });

  final TimelineClip clip;
  final bool selected;
  final bool allowEditing;
  final bool enableLiveFrames;
  final bool isPlaying;
  final double playheadSeconds;
  final int previewSeekVersion;
  final Size canvasSize;
  final VoidCallback onSelect;
  final ValueChanged<Offset> onMove;

  @override
  Widget build(BuildContext context) {
    const aspectRatio = 16 / 9;
    final baseWidth = math.min(
      canvasSize.width * 0.76,
      canvasSize.height * aspectRatio * 0.78,
    );
    final layerWidth = (baseWidth * clip.scale).clamp(
      48.0,
      canvasSize.width * 1.6,
    );
    final layerHeight = layerWidth / aspectRatio;
    final rawTransitionProgress =
        clip.transition == TimelineTransition.cut ||
            clip.timelineStartSeconds <= 0
        ? 1.0
        : ((playheadSeconds - clip.timelineStartSeconds) /
                  clip.transitionDurationSeconds)
              .clamp(0.0, 1.0)
              .toDouble();
    final transitionProgress =
        rawTransitionProgress *
        rawTransitionProgress *
        (3 - 2 * rawTransitionProgress);
    final slideDistance = 1 - transitionProgress;
    final slideX = switch (clip.transition) {
      TimelineTransition.slideLeft ||
      TimelineTransition.wipeLeft ||
      TimelineTransition.whipPan => canvasSize.width * slideDistance,
      TimelineTransition.slideRight ||
      TimelineTransition.wipeRight => -canvasSize.width * slideDistance,
      _ => 0.0,
    };
    final slideY = switch (clip.transition) {
      TimelineTransition.slideUp ||
      TimelineTransition.wipeUp => canvasSize.height * slideDistance,
      TimelineTransition.slideDown ||
      TimelineTransition.wipeDown => -canvasSize.height * slideDistance,
      _ => 0.0,
    };
    final transitionOpacity =
        clip.transition == TimelineTransition.dissolve ||
            clip.transition == TimelineTransition.fadeThroughBlack
        ? transitionProgress
        : 1.0;
    final left =
        (canvasSize.width - layerWidth) / 2 +
        clip.x * canvasSize.width / 2 +
        slideX;
    final top =
        (canvasSize.height - layerHeight) / 2 +
        clip.y * canvasSize.height / 2 +
        slideY;
    final thumbnailPath = clip.thumbnailPath;
    final thumbnailFile = thumbnailPath == null ? null : File(thumbnailPath);
    final hasThumbnail = thumbnailFile?.existsSync() ?? false;
    final hasStarted = playheadSeconds >= clip.timelineStartSeconds;
    final streamIsPlaying = isPlaying && hasStarted;

    return Positioned(
      left: left,
      top: top,
      width: layerWidth,
      height: layerHeight,
      child: Opacity(
        opacity: hasStarted ? clip.opacity * transitionOpacity : 0,
        child: IgnorePointer(
          ignoring: !hasStarted,
          child: MouseRegion(
            cursor: selected && !clip.locked && allowEditing
                ? SystemMouseCursors.move
                : SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onSelect,
              onPanUpdate: selected && !clip.locked && allowEditing
                  ? (details) {
                      onMove(
                        Offset(
                          details.delta.dx / canvasSize.width * 2,
                          details.delta.dy / canvasSize.height * 2,
                        ),
                      );
                    }
                  : null,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF181818),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFFFFFFFF)
                        : const Color(0x80FFFFFF),
                    width: selected ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 24,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(
                          sigmaX: clip.panningBlurIntensity * 4,
                        ),
                        child: ColorFiltered(
                          colorFilter: ColorFilter.matrix(
                            _previewColorMatrix(clip),
                          ),
                          child: _LiveFramePreview(
                            clip: clip,
                            playheadSeconds: playheadSeconds,
                            previewSeekVersion: previewSeekVersion,
                            isPlaying: streamIsPlaying,
                            enabled: enableLiveFrames,
                            fallback: hasThumbnail
                                ? Image.file(
                                    thumbnailFile!,
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                  )
                                : const Center(
                                    child: Icon(
                                      Icons.movie_creation_outlined,
                                      color: Color(0xDDFFFFFF),
                                      size: 36,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      if (streamIsPlaying)
                        const Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(
                              Icons.play_arrow,
                              color: Color(0xCCFFFFFF),
                              size: 18,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BlurredPreviewBackground extends StatelessWidget {
  const _BlurredPreviewBackground({
    required this.clip,
    required this.playheadSeconds,
    required this.previewSeekVersion,
    required this.enabled,
    required this.isPlaying,
  });

  final TimelineClip clip;
  final double playheadSeconds;
  final int previewSeekVersion;
  final bool enabled;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    final thumbnailPath = clip.thumbnailPath;
    final thumbnailFile = thumbnailPath == null ? null : File(thumbnailPath);
    final fallback = thumbnailFile?.existsSync() ?? false
        ? Image.file(thumbnailFile!, fit: BoxFit.cover, gaplessPlayback: true)
        : const SizedBox.shrink();

    return ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: Transform.scale(
        scale: 1.18,
        child: Opacity(
          opacity: 0.72,
          child: ColorFiltered(
            colorFilter: ColorFilter.matrix(_previewColorMatrix(clip)),
            child: _LiveFramePreview(
              clip: clip,
              playheadSeconds: playheadSeconds,
              previewSeekVersion: previewSeekVersion,
              isPlaying: isPlaying,
              enabled: enabled,
              fallback: fallback,
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveFramePreview extends StatefulWidget {
  const _LiveFramePreview({
    required this.clip,
    required this.playheadSeconds,
    required this.previewSeekVersion,
    required this.isPlaying,
    required this.enabled,
    required this.fallback,
  });

  final TimelineClip clip;
  final double playheadSeconds;
  final int previewSeekVersion;
  final bool isPlaying;
  final bool enabled;
  final Widget fallback;

  @override
  State<_LiveFramePreview> createState() => _LiveFramePreviewState();
}

class _LiveFramePreviewState extends State<_LiveFramePreview> {
  String? _framePath;
  String? _requestedFrameKey;
  Timer? _sourceSyncTimer;
  late final FrameStreamPlayer _streamPlayer = FrameStreamPlayer(
    onFrame: _handleStreamFrame,
  );
  ui.Image? _streamImage;
  ui.Image? _previousStreamImage;

  @override
  void initState() {
    super.initState();
    _syncPreviewSource();
  }

  @override
  void didUpdateWidget(covariant _LiveFramePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final clipChanged = oldWidget.clip.id != widget.clip.id;
    final enabledChanged = oldWidget.enabled != widget.enabled;
    final playbackChanged = oldWidget.isPlaying != widget.isPlaying;
    final playbackPipelineChanged =
        oldWidget.clip.speed != widget.clip.speed ||
        oldWidget.clip.reverse != widget.clip.reverse ||
        oldWidget.clip.trimStartSeconds != widget.clip.trimStartSeconds ||
        oldWidget.clip.trimEndSeconds != widget.clip.trimEndSeconds ||
        oldWidget.clip.path != widget.clip.path;
    final explicitlySeeked =
        oldWidget.previewSeekVersion != widget.previewSeekVersion;
    final seekedWhilePaused =
        !widget.isPlaying &&
        oldWidget.playheadSeconds != widget.playheadSeconds;
    final jumpedWhilePlaying =
        widget.isPlaying &&
        (oldWidget.playheadSeconds - widget.playheadSeconds).abs() > 0.5;
    if (clipChanged ||
        enabledChanged ||
        playbackChanged ||
        playbackPipelineChanged ||
        explicitlySeeked ||
        seekedWhilePaused ||
        jumpedWhilePlaying) {
      _schedulePreviewSourceSync(
        debounce: explicitlySeeked || seekedWhilePaused || jumpedWhilePlaying,
      );
    }
  }

  @override
  void dispose() {
    _sourceSyncTimer?.cancel();
    _streamPlayer.dispose();
    _previousStreamImage?.dispose();
    _streamImage?.dispose();
    super.dispose();
  }

  void _handleStreamFrame(ui.Image image) {
    if (!mounted || !widget.isPlaying || !widget.enabled) {
      image.dispose();
      return;
    }
    setState(() {
      // Dispose the grandparent frame: the parent may still be painting.
      _previousStreamImage?.dispose();
      _previousStreamImage = _streamImage;
      _streamImage = image;
    });
  }

  void _clearStreamImage() {
    _previousStreamImage?.dispose();
    _previousStreamImage = null;
    final image = _streamImage;
    _streamImage = null;
    if (image != null) {
      // The current frame may still be referenced by the last paint.
      WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
    }
  }

  void _schedulePreviewSourceSync({bool debounce = false}) {
    _sourceSyncTimer?.cancel();
    if (!debounce) {
      _syncPreviewSource();
      return;
    }
    if (widget.isPlaying) {
      _streamPlayer.stop();
    }
    _sourceSyncTimer = Timer(const Duration(milliseconds: 60), () {
      if (mounted) {
        _syncPreviewSource();
      }
    });
  }

  void _syncPreviewSource() {
    _sourceSyncTimer?.cancel();
    if (!widget.enabled) {
      _streamPlayer.stop();
      return;
    }

    if (widget.isPlaying) {
      unawaited(_startStream());
    } else {
      _streamPlayer.stop();
      unawaited(_loadFrame());
    }
  }

  Future<void> _startStream() async {
    final sourceSeconds = _sourceSeconds();
    final speed = widget.clip.speed.clamp(0.1, 100.0).toDouble();
    final previewFrameRate = widget.clip.sourceFrameRate
        .clamp(12.0, 30.0)
        .toDouble();

    if (widget.clip.reverse) {
      final remaining = sourceSeconds - widget.clip.trimStartSeconds;
      if (remaining <= 0) {
        _streamPlayer.stop();
        return;
      }
      await _streamPlayer.playReverse(
        inputPath: widget.clip.path,
        endSeconds: sourceSeconds,
        floorSeconds: widget.clip.trimStartSeconds,
        displayFps: previewFrameRate,
        speed: speed,
      );
    } else {
      final remaining = widget.clip.trimEndSeconds - sourceSeconds;
      if (remaining <= 0) {
        _streamPlayer.stop();
        return;
      }
      await _streamPlayer.playForward(
        inputPath: widget.clip.path,
        startSeconds: sourceSeconds,
        sourceDurationSeconds: remaining,
        displayFps: previewFrameRate,
        speed: speed,
      );
    }
  }

  Future<void> _loadFrame() async {
    final sourceSeconds = _sourceSeconds();
    final frameRate = widget.clip.sourceFrameRate.clamp(1.0, 120.0).toDouble();
    final frameIndex = (sourceSeconds * frameRate).floor();
    final frameSeconds = frameIndex / frameRate;
    final frameKey =
        '${widget.clip.id}_hq3_'
        '${widget.clip.reverse ? 'rev' : 'fwd'}_'
        '${frameIndex}_'
        '${_ffmpegNumber(widget.clip.speed)}_'
        '${_ffmpegNumber(widget.clip.trimStartSeconds)}_'
        '${_ffmpegNumber(widget.clip.trimEndSeconds)}';
    if (_requestedFrameKey == frameKey) {
      return;
    }
    _requestedFrameKey = frameKey;

    try {
      final cacheDirectory = Directory(
        p.join(Directory.systemTemp.path, 'content_maker_preview_frames'),
      );
      await cacheDirectory.create(recursive: true);
      final outputPath = p.join(cacheDirectory.path, '$frameKey.jpg');
      final outputFile = File(outputPath);

      if (!outputFile.existsSync()) {
        // -ss before -i: keyframe-seek then decode to the exact frame, which
        // is dramatically faster than decoding from the start of the file.
        await Process.run(FfmpegExecutables.ffmpeg, <String>[
          '-y',
          '-hide_banner',
          '-loglevel',
          'error',
          '-ss',
          _ffmpegNumber(frameSeconds),
          '-i',
          widget.clip.path,
          '-frames:v',
          '1',
          '-vf',
          'scale=w=min(iw\\,1600):h=-2:flags=lanczos',
          '-q:v',
          '2',
          outputPath,
        ]);
      }

      if (!mounted ||
          _requestedFrameKey != frameKey ||
          !outputFile.existsSync()) {
        return;
      }

      setState(() {
        _framePath = outputPath;
        // A fresh still supersedes whatever streaming frame was left behind.
        _clearStreamImage();
      });
    } catch (_) {
      return;
    }
  }

  double _sourceSeconds() {
    final timelineOffset =
        (widget.playheadSeconds - widget.clip.timelineStartSeconds)
            .clamp(0.0, widget.clip.durationSeconds)
            .toDouble();
    final sourceOffset = timelineOffset * widget.clip.speed.clamp(0.1, 100.0);
    final frameRate = widget.clip.sourceFrameRate.clamp(1.0, 120.0);
    final lastFrameSeconds = math.max(
      widget.clip.trimStartSeconds,
      widget.clip.trimEndSeconds - (1 / frameRate),
    );
    if (widget.clip.reverse) {
      return (lastFrameSeconds - sourceOffset)
          .clamp(widget.clip.trimStartSeconds, widget.clip.trimEndSeconds)
          .toDouble();
    }
    return (widget.clip.trimStartSeconds + sourceOffset)
        .clamp(widget.clip.trimStartSeconds, widget.clip.trimEndSeconds)
        .toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final streamImage = _streamImage;
    if (widget.enabled && streamImage != null) {
      return RawImage(
        image: streamImage,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        isAntiAlias: true,
      );
    }

    final framePath = _framePath;
    if (!widget.enabled || framePath == null || !File(framePath).existsSync()) {
      return widget.fallback;
    }

    return Image.file(
      File(framePath),
      key: ValueKey(framePath),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.high,
      isAntiAlias: true,
    );
  }
}

class _TimelinePanel extends StatefulWidget {
  const _TimelinePanel({
    required this.clips,
    required this.selectedClipId,
    required this.playheadSeconds,
    required this.timelineDuration,
    required this.onPlayheadChanged,
    required this.onSelectClip,
    required this.onMoveClip,
    required this.onTrimClipStart,
    required this.onTrimClipEnd,
    required this.onDuplicateClip,
    required this.onSplitClip,
    required this.onDeleteClip,
    required this.onDropMediaClip,
    required this.onDropTransition,
  });

  final List<TimelineClip> clips;
  final String? selectedClipId;
  final double playheadSeconds;
  final double timelineDuration;
  final ValueChanged<double> onPlayheadChanged;
  final ValueChanged<String> onSelectClip;
  final void Function(String clipId, double deltaSeconds) onMoveClip;
  final void Function(String clipId, double deltaSeconds) onTrimClipStart;
  final void Function(String clipId, double deltaSeconds) onTrimClipEnd;
  final ValueChanged<String> onDuplicateClip;
  final ValueChanged<String> onSplitClip;
  final ValueChanged<String> onDeleteClip;
  final void Function(
    TimelineClip clip,
    TimelineClipType trackType,
    int trackIndex,
    double timelineSeconds,
  )
  onDropMediaClip;
  final void Function(
    TimelineTransition transition,
    int trackIndex,
    double timelineSeconds, {
    String? sourceClipId,
  })
  onDropTransition;

  @override
  State<_TimelinePanel> createState() => _TimelinePanelState();
}

class _TimelinePanelState extends State<_TimelinePanel> {
  double _pixelsPerSecond = 72;
  double? _dragPlayheadSeconds;

  @override
  Widget build(BuildContext context) {
    final pixelsPerSecond = _pixelsPerSecond;
    final timelineWidth = widget.timelineDuration * pixelsPerSecond;
    final tracks = _buildTracks(widget.clips);
    final markerStepSeconds = _markerStepSeconds(pixelsPerSecond);
    final selectedClip = widget.clips
        .where((clip) => clip.id == widget.selectedClipId)
        .firstOrNull;

    return _EditorPanel(
      title: 'Timeline',
      actions: [
        _InfoChip(
          icon: Icons.av_timer_outlined,
          label: _seconds(widget.timelineDuration),
        ),
        _InfoChip(
          icon: Icons.zoom_in_outlined,
          label: markerStepSeconds < 1
              ? '${markerStepSeconds.toStringAsFixed(1)}s'
              : '${markerStepSeconds.toStringAsFixed(0)}s',
        ),
      ],
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            final scale = event.scrollDelta.dy < 0 ? 1.15 : 1 / 1.15;
            setState(() {
              _pixelsPerSecond = (_pixelsPerSecond * scale)
                  .clamp(4.0, 220.0)
                  .toDouble();
            });
          }
        },
        child: Scrollbar(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) {
                widget.onPlayheadChanged(
                  (details.localPosition.dx / pixelsPerSecond)
                      .clamp(0.0, widget.timelineDuration)
                      .toDouble(),
                );
              },
              child: SizedBox(
                width: timelineWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 28,
                      child: _TimelineRuler(
                        timelineDuration: widget.timelineDuration,
                        pixelsPerSecond: pixelsPerSecond,
                        markerStepSeconds: markerStepSeconds,
                      ),
                    ),
                    Expanded(
                      child: Stack(
                        children: [
                          Column(
                            children: [
                              for (final track in tracks)
                                Expanded(
                                  child: _TimelineTrackRow(
                                    track: track,
                                    clips: widget.clips
                                        .where(
                                          (clip) =>
                                              clip.type == track.type &&
                                              clip.trackIndex == track.index,
                                        )
                                        .toList(),
                                    selectedClipId: widget.selectedClipId,
                                    pixelsPerSecond: pixelsPerSecond,
                                    onPlayheadChanged: widget.onPlayheadChanged,
                                    onSelectClip: widget.onSelectClip,
                                    onMoveClip: widget.onMoveClip,
                                    onTrimClipStart: widget.onTrimClipStart,
                                    onTrimClipEnd: widget.onTrimClipEnd,
                                    onDuplicateClip: widget.onDuplicateClip,
                                    onSplitClip: widget.onSplitClip,
                                    onDeleteClip: widget.onDeleteClip,
                                    onDropMediaClip: widget.onDropMediaClip,
                                    onDropTransition: widget.onDropTransition,
                                  ),
                                ),
                            ],
                          ),
                          if (selectedClip != null)
                            Positioned(
                              left:
                                  selectedClip.timelineEndSeconds *
                                      pixelsPerSecond -
                                  40,
                              top: 0,
                              bottom: 0,
                              width: 80,
                              child: IgnorePointer(
                                child: Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 2,
                                      ),
                                      color: const Color(0xFF6F97A5),
                                      child: Text(
                                        'END ${_seconds(selectedClip.timelineEndSeconds)}',
                                        maxLines: 1,
                                        style: const TextStyle(
                                          color: Color(0xFF050505),
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Center(
                                        child: Container(
                                          width: 1,
                                          color: const Color(0xFF6F97A5),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          Positioned(
                            left: widget.playheadSeconds * pixelsPerSecond - 8,
                            top: 0,
                            bottom: 0,
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onHorizontalDragStart: (_) {
                                _dragPlayheadSeconds = widget.playheadSeconds;
                              },
                              onHorizontalDragUpdate: (details) {
                                final next =
                                    (_dragPlayheadSeconds ??
                                        widget.playheadSeconds) +
                                    details.delta.dx / pixelsPerSecond;
                                _dragPlayheadSeconds = next
                                    .clamp(0.0, widget.timelineDuration)
                                    .toDouble();
                                widget.onPlayheadChanged(_dragPlayheadSeconds!);
                              },
                              onHorizontalDragEnd: (_) {
                                _dragPlayheadSeconds = null;
                              },
                              onHorizontalDragCancel: () {
                                _dragPlayheadSeconds = null;
                              },
                              child: SizedBox(
                                width: 16,
                                child: Center(
                                  child: Container(
                                    width: 3,
                                    color: const Color(0xFFFFF2A6),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  double _markerStepSeconds(double pixelsPerSecond) {
    if (pixelsPerSecond >= 120) {
      return 0.5;
    }
    if (pixelsPerSecond >= 64) {
      return 1;
    }
    if (pixelsPerSecond >= 36) {
      return 2;
    }
    if (pixelsPerSecond >= 18) {
      return 5;
    }
    if (pixelsPerSecond >= 9) {
      return 10;
    }
    return 20;
  }

  List<_TrackSpec> _buildTracks(List<TimelineClip> clips) {
    final tracks = <_TrackSpec>[];
    final videoTrackCount = math.max(
      1,
      clips
              .where((clip) => clip.isVideo)
              .map((clip) => clip.trackIndex)
              .fold<int>(0, math.max) +
          1,
    );
    final audioTrackCount = math.max(
      1,
      clips
              .where((clip) => clip.isAudio)
              .map((clip) => clip.trackIndex)
              .fold<int>(0, math.max) +
          1,
    );

    for (var i = videoTrackCount - 1; i >= 0; i--) {
      tracks.add(_TrackSpec(TimelineClipType.video, i));
    }
    for (var i = 0; i < audioTrackCount; i++) {
      tracks.add(_TrackSpec(TimelineClipType.audio, i));
    }
    return tracks;
  }
}

class _TrackSpec {
  const _TrackSpec(this.type, this.index);

  final TimelineClipType type;
  final int index;

  String get label {
    return type == TimelineClipType.video ? 'V${index + 1}' : 'A${index + 1}';
  }
}

class _TimelineRuler extends StatelessWidget {
  const _TimelineRuler({
    required this.timelineDuration,
    required this.pixelsPerSecond,
    required this.markerStepSeconds,
  });

  final double timelineDuration;
  final double pixelsPerSecond;
  final double markerStepSeconds;

  @override
  Widget build(BuildContext context) {
    final markers = (timelineDuration / markerStepSeconds).ceil();
    return Stack(
      children: [
        for (var marker = 0; marker <= markers; marker++)
          Positioned(
            left: marker * markerStepSeconds * pixelsPerSecond,
            top: 0,
            bottom: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 1, height: 8, color: const Color(0xFF5C5C5C)),
                Text(
                  _rulerLabel(marker * markerStepSeconds),
                  style: const TextStyle(
                    color: Color(0xFF9A9A9A),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _rulerLabel(double seconds) {
    if (seconds == seconds.roundToDouble()) {
      return '${seconds.round()}s';
    }
    return '${seconds.toStringAsFixed(1)}s';
  }
}

class _TimelineTrackRow extends StatelessWidget {
  const _TimelineTrackRow({
    required this.track,
    required this.clips,
    required this.selectedClipId,
    required this.pixelsPerSecond,
    required this.onPlayheadChanged,
    required this.onSelectClip,
    required this.onMoveClip,
    required this.onTrimClipStart,
    required this.onTrimClipEnd,
    required this.onDuplicateClip,
    required this.onSplitClip,
    required this.onDeleteClip,
    required this.onDropMediaClip,
    required this.onDropTransition,
  });

  final _TrackSpec track;
  final List<TimelineClip> clips;
  final String? selectedClipId;
  final double pixelsPerSecond;
  final ValueChanged<double> onPlayheadChanged;
  final ValueChanged<String> onSelectClip;
  final void Function(String clipId, double deltaSeconds) onMoveClip;
  final void Function(String clipId, double deltaSeconds) onTrimClipStart;
  final void Function(String clipId, double deltaSeconds) onTrimClipEnd;
  final ValueChanged<String> onDuplicateClip;
  final ValueChanged<String> onSplitClip;
  final ValueChanged<String> onDeleteClip;
  final void Function(
    TimelineClip clip,
    TimelineClipType trackType,
    int trackIndex,
    double timelineSeconds,
  )
  onDropMediaClip;
  final void Function(
    TimelineTransition transition,
    int trackIndex,
    double timelineSeconds, {
    String? sourceClipId,
  })
  onDropTransition;

  @override
  Widget build(BuildContext context) {
    return DragTarget<_TimelineDragPayload>(
      onWillAcceptWithDetails: (details) {
        final data = details.data;
        return switch (data) {
          _MediaClipDragPayload() => data.clip.type == track.type,
          _TransitionDragPayload() => track.type == TimelineClipType.video,
        };
      },
      onAcceptWithDetails: (details) {
        final renderBox = context.findRenderObject() as RenderBox;
        final localPosition = renderBox.globalToLocal(details.offset);
        final seconds = math.max(0.0, localPosition.dx / pixelsPerSecond);
        switch (details.data) {
          case _MediaClipDragPayload(:final clip):
            onDropMediaClip(clip, track.type, track.index, seconds);
          case _TransitionDragPayload(:final transition, :final sourceClipId):
            onDropTransition(
              transition,
              track.index,
              seconds,
              sourceClipId: sourceClipId,
            );
        }
      },
      builder: (context, candidateData, rejectedData) {
        final acceptingDrop = candidateData.isNotEmpty;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: acceptingDrop ? const Color(0x223FAF86) : Colors.transparent,
            border: Border(
              top: const BorderSide(color: Color(0xFF2A2A2A)),
              bottom: acceptingDrop
                  ? const BorderSide(color: Color(0xFF6F97A5))
                  : BorderSide.none,
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xE6101010),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(
                      track.label,
                      style: const TextStyle(
                        color: Color(0xFFD0D0D0),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              for (final clip in clips)
                Positioned(
                  left: clip.timelineStartSeconds * pixelsPerSecond,
                  top: 8,
                  bottom: 8,
                  width: math.max(54, clip.durationSeconds * pixelsPerSecond),
                  child: _TimelineClipBlock(
                    clip: clip,
                    selected: clip.id == selectedClipId,
                    pixelsPerSecond: pixelsPerSecond,
                    onTap: () => onSelectClip(clip.id),
                    onDrag: (delta) {
                      onMoveClip(clip.id, delta.dx / pixelsPerSecond);
                    },
                    onTrimStart: (delta) {
                      onTrimClipStart(clip.id, delta.dx / pixelsPerSecond);
                    },
                    onTrimEnd: (delta) {
                      onTrimClipEnd(clip.id, delta.dx / pixelsPerSecond);
                    },
                    onContextPositionChanged: (localPosition) {
                      final seconds =
                          clip.timelineStartSeconds +
                          localPosition.dx / pixelsPerSecond;
                      onPlayheadChanged(
                        seconds
                            .clamp(
                              clip.timelineStartSeconds,
                              clip.timelineEndSeconds,
                            )
                            .toDouble(),
                      );
                    },
                    onDuplicate: () => onDuplicateClip(clip.id),
                    onSplit: () => onSplitClip(clip.id),
                    onDelete: () => onDeleteClip(clip.id),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TimelineClipBlock extends StatelessWidget {
  const _TimelineClipBlock({
    required this.clip,
    required this.selected,
    required this.pixelsPerSecond,
    required this.onTap,
    required this.onDrag,
    required this.onTrimStart,
    required this.onTrimEnd,
    required this.onContextPositionChanged,
    required this.onDuplicate,
    required this.onSplit,
    required this.onDelete,
  });

  final TimelineClip clip;
  final bool selected;
  final double pixelsPerSecond;
  final VoidCallback onTap;
  final ValueChanged<Offset> onDrag;
  final ValueChanged<Offset> onTrimStart;
  final ValueChanged<Offset> onTrimEnd;
  final ValueChanged<Offset> onContextPositionChanged;
  final VoidCallback onDuplicate;
  final VoidCallback onSplit;
  final VoidCallback onDelete;

  Future<void> _showClipMenu(
    BuildContext context,
    Offset position,
    double clickedOffsetSeconds,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final canTrimStart =
        !clip.locked &&
        clickedOffsetSeconds > 0.1 &&
        clickedOffsetSeconds < clip.durationSeconds;
    final canSplitAtPosition =
        !clip.locked &&
        clickedOffsetSeconds > 0.1 &&
        clickedOffsetSeconds < clip.durationSeconds - 0.1;
    final canTrimEnd =
        !clip.locked &&
        clickedOffsetSeconds > 0 &&
        clickedOffsetSeconds < clip.durationSeconds - 0.1;
    final action = await showMenu<_TimelineClipAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(position, position),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: _TimelineClipAction.trimStartToCursor,
          enabled: canTrimStart,
          child: const _MenuRow(
            icon: Icons.first_page_outlined,
            label: 'Trim start here',
          ),
        ),
        PopupMenuItem(
          value: _TimelineClipAction.split,
          enabled: canSplitAtPosition,
          child: const _MenuRow(
            icon: Icons.content_cut_outlined,
            label: 'Cut here',
          ),
        ),
        PopupMenuItem(
          value: _TimelineClipAction.trimEndToCursor,
          enabled: canTrimEnd,
          child: const _MenuRow(
            icon: Icons.last_page_outlined,
            label: 'Trim end here',
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _TimelineClipAction.duplicate,
          enabled: !clip.locked,
          child: const _MenuRow(icon: Icons.copy_outlined, label: 'Duplicate'),
        ),
        PopupMenuItem(
          value: _TimelineClipAction.delete,
          enabled: !clip.locked,
          child: const _MenuRow(icon: Icons.delete_outline, label: 'Delete'),
        ),
      ],
    );

    switch (action) {
      case _TimelineClipAction.trimStartToCursor:
        onTrimStart(Offset(clickedOffsetSeconds * pixelsPerSecond, 0));
        break;
      case _TimelineClipAction.duplicate:
        onDuplicate();
        break;
      case _TimelineClipAction.split:
        onSplit();
        break;
      case _TimelineClipAction.trimEndToCursor:
        onTrimEnd(
          Offset(
            (clickedOffsetSeconds - clip.durationSeconds) * pixelsPerSecond,
            0,
          ),
        );
        break;
      case _TimelineClipAction.delete:
        onDelete();
        break;
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = clip.isVideo
        ? const Color(0xFF466C7A)
        : const Color(0xFF466B52);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onSecondaryTapDown: (details) {
        onTap();
        onContextPositionChanged(details.localPosition);
        final clickedOffsetSeconds =
            (details.localPosition.dx / pixelsPerSecond)
                .clamp(0.0, clip.durationSeconds)
                .toDouble();
        _showClipMenu(context, details.globalPosition, clickedOffsetSeconds);
      },
      child: Opacity(
        opacity: clip.enabled ? 1 : 0.42,
        child: Material(
          color: color.withValues(alpha: selected ? 0.95 : 0.78),
          borderRadius: BorderRadius.circular(10),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected
                    ? const Color(0xFFFFFFFF)
                    : const Color(0x66FFFFFF),
                width: selected ? 2 : 1,
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  onHorizontalDragUpdate: clip.locked
                      ? null
                      : (details) => onDrag(details.delta),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          clip.isVideo
                              ? Icons.movie_creation_outlined
                              : Icons.graphic_eq_outlined,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            clip.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFF1F1F1),
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (clip.isVideo && clip.transition != TimelineTransition.cut)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: math.min(
                      clip.durationSeconds * pixelsPerSecond,
                      math.max(
                        12,
                        clip.transitionDurationSeconds * pixelsPerSecond,
                      ),
                    ),
                    child: IgnorePointer(
                      child: Container(
                        color: const Color(0x2EFFFFFF),
                        foregroundDecoration: const BoxDecoration(
                          border: Border(
                            right: BorderSide(
                              color: Color(0xFFDFDFDF),
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (clip.isVideo && clip.transition != TimelineTransition.cut)
                  Positioned(
                    top: 3,
                    right: 12,
                    child: Draggable<_TimelineDragPayload>(
                      data: _TransitionDragPayload(
                        clip.transition,
                        sourceClipId: clip.id,
                      ),
                      dragAnchorStrategy: pointerDragAnchorStrategy,
                      feedback: Material(
                        color: Colors.transparent,
                        child: _TransitionDragChip(
                          transition: clip.transition,
                          active: true,
                        ),
                      ),
                      childWhenDragging: Opacity(
                        opacity: 0.35,
                        child: _TransitionDragChip(transition: clip.transition),
                      ),
                      child: _TransitionDragChip(transition: clip.transition),
                    ),
                  ),
                if (!clip.locked) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _TrimHandle(
                      tooltip: 'Trim start',
                      onDrag: onTrimStart,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _TrimHandle(tooltip: 'Trim end', onDrag: onTrimEnd),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrimHandle extends StatelessWidget {
  const _TrimHandle({required this.tooltip, required this.onDrag});

  final String tooltip;
  final ValueChanged<Offset> onDrag;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (details) => onDrag(details.delta),
          child: SizedBox(
            width: 12,
            child: Center(
              child: Container(
                width: 3,
                height: 22,
                decoration: BoxDecoration(
                  color: const Color(0xDDFFFFFF),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TransitionDragChip extends StatelessWidget {
  const _TransitionDragChip({required this.transition, this.active = false});

  final TimelineTransition transition;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Drag ${_transitionName(transition)}',
      child: Container(
        padding: const EdgeInsets.all(3),
        color: active ? const Color(0xFF303030) : const Color(0xCC111111),
        child: Icon(
          _transitionIconData(transition),
          size: 14,
          color: const Color(0xFFE8E8E8),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [Icon(icon, size: 18), const SizedBox(width: 10), Text(label)],
    );
  }
}

class _AdvancedVideoInspectorPanel extends StatelessWidget {
  const _AdvancedVideoInspectorPanel({
    required this.clip,
    required this.timelineDuration,
    required this.onClipChanged,
  });

  final TimelineClip clip;
  final double timelineDuration;
  final ValueChanged<TimelineClip> onClipChanged;

  @override
  Widget build(BuildContext context) {
    final sourceDuration = math.max(clip.sourceDurationSeconds ?? 3600.0, 0.1);
    return _EditorPanel(
      title: 'Inspector',
      child: DefaultTabController(
        length: 5,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.movie_creation_outlined,
                  color: Color(0xFF6F97A5),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    clip.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: const [
                Tab(icon: Icon(Icons.open_with_outlined), text: 'Transform'),
                Tab(icon: Icon(Icons.color_lens_outlined), text: 'Grade'),
                Tab(icon: Icon(Icons.filter_vintage_outlined), text: 'Filters'),
                Tab(
                  icon: Icon(Icons.motion_photos_on_outlined),
                  text: 'Motion',
                ),
                Tab(icon: Icon(Icons.auto_awesome_motion), text: 'Transitions'),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                children: [
                  _inspectorTab([
                    SegmentedButton<int>(
                      segments: [
                        for (var i = 0; i < 3; i++)
                          ButtonSegment(value: i, label: Text('V${i + 1}')),
                      ],
                      selected: {clip.trackIndex.clamp(0, 2).toInt()},
                      onSelectionChanged: clip.locked
                          ? null
                          : (selection) => onClipChanged(
                              clip.copyWith(trackIndex: selection.first),
                            ),
                    ),
                    const SizedBox(height: 12),
                    _ValueControl(
                      icon: Icons.start_outlined,
                      label: 'Timeline start',
                      value: clip.timelineStartSeconds,
                      min: 0,
                      max: math.max(
                        timelineDuration,
                        clip.timelineStartSeconds + 1,
                      ),
                      divisions: 200,
                      displayValue: _seconds(clip.timelineStartSeconds),
                      onChanged: clip.locked
                          ? null
                          : (value) => onClipChanged(
                              clip.copyWith(timelineStartSeconds: value),
                            ),
                    ),
                    _ValueControl(
                      icon: Icons.content_cut_outlined,
                      label: 'Source in',
                      value: clip.trimStartSeconds,
                      min: 0,
                      max: math.max(
                        0.1,
                        math.min(
                          clip.trimEndSeconds - 0.1,
                          sourceDuration - 0.1,
                        ),
                      ),
                      divisions: 200,
                      displayValue: _seconds(clip.trimStartSeconds),
                      onChanged: clip.locked
                          ? null
                          : (value) => onClipChanged(
                              clip.copyWith(trimStartSeconds: value),
                            ),
                    ),
                    _ValueControl(
                      icon: Icons.flag_outlined,
                      label: 'Source out',
                      value: clip.trimEndSeconds,
                      min: clip.trimStartSeconds + 0.1,
                      max: math.max(
                        clip.trimStartSeconds + 0.1,
                        sourceDuration,
                      ),
                      divisions: 300,
                      displayValue: _seconds(clip.trimEndSeconds),
                      onChanged: clip.locked
                          ? null
                          : (value) => onClipChanged(
                              clip.copyWith(trimEndSeconds: value),
                            ),
                    ),
                    _ValueControl(
                      icon: Icons.open_with_outlined,
                      label: 'Horizontal',
                      value: clip.x,
                      min: -1.5,
                      max: 1.5,
                      divisions: 120,
                      displayValue: _signed(clip.x),
                      onChanged: clip.locked
                          ? null
                          : (value) => onClipChanged(clip.copyWith(x: value)),
                    ),
                    _ValueControl(
                      icon: Icons.height_outlined,
                      label: 'Vertical',
                      value: clip.y,
                      min: -1.5,
                      max: 1.5,
                      divisions: 120,
                      displayValue: _signed(clip.y),
                      onChanged: clip.locked
                          ? null
                          : (value) => onClipChanged(clip.copyWith(y: value)),
                    ),
                    _ValueControl(
                      icon: Icons.zoom_out_map_outlined,
                      label: 'Scale',
                      value: clip.scale,
                      min: 0.1,
                      max: 3,
                      divisions: 145,
                      displayValue: '${(clip.scale * 100).round()}%',
                      onChanged: clip.locked
                          ? null
                          : (value) =>
                                onClipChanged(clip.copyWith(scale: value)),
                    ),
                    _ValueControl(
                      icon: Icons.opacity_outlined,
                      label: 'Opacity',
                      value: clip.opacity,
                      min: 0,
                      max: 1,
                      divisions: 100,
                      displayValue: '${(clip.opacity * 100).round()}%',
                      onChanged: clip.locked
                          ? null
                          : (value) =>
                                onClipChanged(clip.copyWith(opacity: value)),
                    ),
                    _clipSwitches(),
                  ]),
                  _inspectorTab([
                    const Text(
                      'Look presets',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final preset in const [
                          'Natural',
                          'Enhanced',
                          'Vibrant',
                          'Dark',
                          'Cinematic',
                        ])
                          ActionChip(
                            label: Text(preset),
                            onPressed: clip.locked
                                ? null
                                : () => onClipChanged(
                                    _applyGradePreset(clip, preset),
                                  ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _ValueControl(
                      icon: Icons.exposure_outlined,
                      label: 'Exposure',
                      value: clip.brightness,
                      min: -0.5,
                      max: 0.5,
                      divisions: 100,
                      displayValue: _signed(clip.brightness),
                      onChanged: clip.locked
                          ? null
                          : (value) =>
                                onClipChanged(clip.copyWith(brightness: value)),
                    ),
                    _ValueControl(
                      icon: Icons.palette_outlined,
                      label: 'Saturation',
                      value: clip.saturation,
                      min: 0,
                      max: 2,
                      divisions: 100,
                      displayValue: '${(clip.saturation * 100).round()}%',
                      onChanged: clip.locked
                          ? null
                          : (value) =>
                                onClipChanged(clip.copyWith(saturation: value)),
                    ),
                    _ValueControl(
                      icon: Icons.contrast_outlined,
                      label: 'Contrast',
                      value: clip.contrast,
                      min: 0.5,
                      max: 2,
                      divisions: 75,
                      displayValue: '${(clip.contrast * 100).round()}%',
                      onChanged: clip.locked
                          ? null
                          : (value) =>
                                onClipChanged(clip.copyWith(contrast: value)),
                    ),
                    _ValueControl(
                      icon: Icons.brightness_6_outlined,
                      label: 'Gamma',
                      value: clip.gamma,
                      min: 0.5,
                      max: 2,
                      divisions: 75,
                      displayValue: clip.gamma.toStringAsFixed(2),
                      onChanged: clip.locked
                          ? null
                          : (value) =>
                                onClipChanged(clip.copyWith(gamma: value)),
                    ),
                    _ValueControl(
                      icon: Icons.thermostat_outlined,
                      label: 'Temperature',
                      value: clip.temperature,
                      min: -1,
                      max: 1,
                      divisions: 80,
                      displayValue: _signed(clip.temperature),
                      onChanged: clip.locked
                          ? null
                          : (value) => onClipChanged(
                              clip.copyWith(temperature: value),
                            ),
                    ),
                    _ValueControl(
                      icon: Icons.colorize_outlined,
                      label: 'Tint',
                      value: clip.tint,
                      min: -1,
                      max: 1,
                      divisions: 80,
                      displayValue: _signed(clip.tint),
                      onChanged: clip.locked
                          ? null
                          : (value) =>
                                onClipChanged(clip.copyWith(tint: value)),
                    ),
                    _ValueControl(
                      icon: Icons.wb_sunny_outlined,
                      label: 'Highlights',
                      value: clip.highlights,
                      min: -1,
                      max: 1,
                      divisions: 80,
                      displayValue: _signed(clip.highlights),
                      onChanged: clip.locked
                          ? null
                          : (value) =>
                                onClipChanged(clip.copyWith(highlights: value)),
                    ),
                    _ValueControl(
                      icon: Icons.brightness_3_outlined,
                      label: 'Shadows',
                      value: clip.shadows,
                      min: -1,
                      max: 1,
                      divisions: 80,
                      displayValue: _signed(clip.shadows),
                      onChanged: clip.locked
                          ? null
                          : (value) =>
                                onClipChanged(clip.copyWith(shadows: value)),
                    ),
                    _ValueControl(
                      icon: Icons.tonality_outlined,
                      label: 'Fade',
                      value: clip.fade,
                      min: 0,
                      max: 1,
                      divisions: 50,
                      displayValue: '${(clip.fade * 100).round()}%',
                      onChanged: clip.locked
                          ? null
                          : (value) =>
                                onClipChanged(clip.copyWith(fade: value)),
                    ),
                    _ValueControl(
                      icon: Icons.blur_circular_outlined,
                      label: 'Vignette',
                      value: clip.vignette,
                      min: 0,
                      max: 1,
                      divisions: 50,
                      displayValue: '${(clip.vignette * 100).round()}%',
                      onChanged: clip.locked
                          ? null
                          : (value) =>
                                onClipChanged(clip.copyWith(vignette: value)),
                    ),
                    _ValueControl(
                      icon: Icons.details_outlined,
                      label: 'Sharpness',
                      value: clip.sharpness,
                      min: 0,
                      max: 1.5,
                      divisions: 75,
                      displayValue: '${(clip.sharpness * 100).round()}%',
                      onChanged: clip.locked
                          ? null
                          : (value) =>
                                onClipChanged(clip.copyWith(sharpness: value)),
                    ),
                  ]),
                  _inspectorTab([
                    const Text(
                      'Looks',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final preset in const [
                          (id: null, label: 'Natural'),
                          (id: 'cinematic', label: 'Cinematic'),
                          (id: 'retro', label: 'Retro'),
                          (id: 'portrait', label: 'Portrait'),
                          (id: 'mono', label: 'Mono'),
                          (id: 'vlog', label: 'Vlog'),
                        ])
                          ChoiceChip(
                            label: Text(preset.label),
                            selected: preset.id == null
                                ? clip.lutId == null
                                : clip.lutId == preset.id,
                            onSelected: clip.locked
                                ? null
                                : (_) => onClipChanged(
                                    clip.copyWith(
                                      lutId: preset.id,
                                      clearLutId: preset.id == null,
                                      lutIntensity: preset.id == null
                                          ? 1
                                          : clip.lutIntensity,
                                    ),
                                  ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _ValueControl(
                      icon: Icons.opacity_outlined,
                      label: 'Filter strength',
                      value: clip.lutIntensity,
                      min: 0,
                      max: 1,
                      divisions: 100,
                      displayValue: '${(clip.lutIntensity * 100).round()}%',
                      onChanged: clip.locked || clip.lutId == null
                          ? null
                          : (value) => onClipChanged(
                              clip.copyWith(lutIntensity: value),
                            ),
                    ),
                  ]),
                  _inspectorTab([
                    const Text(
                      'Speed',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final speed in const [0.5, 1.0, 2.0, 4.0])
                          ChoiceChip(
                            label: Text(
                              '${speed.toStringAsFixed(speed == 1 ? 0 : 1)}x',
                            ),
                            selected: (clip.speed - speed).abs() < 0.001,
                            onSelected: clip.locked
                                ? null
                                : (_) => onClipChanged(
                                    clip.copyWith(speed: speed),
                                  ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _ValueControl(
                      icon: Icons.speed_outlined,
                      label: 'Speed',
                      value: clip.speed.clamp(0.1, 4.0).toDouble(),
                      min: 0.1,
                      max: 4,
                      divisions: 78,
                      displayValue: '${clip.speed.toStringAsFixed(2)}x',
                      onChanged: clip.locked
                          ? null
                          : (value) =>
                                onClipChanged(clip.copyWith(speed: value)),
                    ),
                    SwitchListTile(
                      value: clip.reverse,
                      onChanged: clip.locked
                          ? null
                          : (value) =>
                                onClipChanged(clip.copyWith(reverse: value)),
                      title: const Text('Reverse'),
                      secondary: const Icon(Icons.replay_outlined),
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<ClipAnimationType>(
                      initialValue: clip.animation.type,
                      decoration: const InputDecoration(
                        labelText: 'Animation',
                        prefixIcon: Icon(Icons.animation_outlined),
                      ),
                      items: [
                        for (final type in ClipAnimationType.values)
                          DropdownMenuItem(
                            value: type,
                            child: Text(_animationLabel(type)),
                          ),
                      ],
                      onChanged: clip.locked
                          ? null
                          : (type) {
                              if (type == null) {
                                return;
                              }
                              onClipChanged(
                                clip.copyWith(
                                  animation: clip.animation.copyWith(
                                    type: type,
                                  ),
                                ),
                              );
                            },
                    ),
                    const SizedBox(height: 14),
                    _ValueControl(
                      icon: Icons.blur_linear_outlined,
                      label: 'Directional blur',
                      value: clip.panningBlurIntensity,
                      min: 0,
                      max: 1,
                      divisions: 20,
                      displayValue:
                          '${(clip.panningBlurIntensity * 100).round()}%',
                      onChanged: clip.locked
                          ? null
                          : (value) => onClipChanged(
                              clip.copyWith(panningBlurIntensity: value),
                            ),
                    ),
                    SwitchListTile(
                      value: clip.motionBlur,
                      onChanged: clip.locked
                          ? null
                          : (value) =>
                                onClipChanged(clip.copyWith(motionBlur: value)),
                      title: const Text('Frame blending'),
                      subtitle: const Text('Smoother fast movement'),
                      secondary: const Icon(Icons.motion_photos_on_outlined),
                      contentPadding: EdgeInsets.zero,
                    ),
                    SwitchListTile(
                      value: clip.motionInterpolation,
                      onChanged: clip.locked
                          ? null
                          : (value) => onClipChanged(
                              clip.copyWith(motionInterpolation: value),
                            ),
                      title: const Text('Motion interpolation'),
                      subtitle: const Text('Higher quality, slower export'),
                      secondary: const Icon(Icons.slow_motion_video_outlined),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ]),
                  _inspectorTab([
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final transition in TimelineTransition.values)
                          ChoiceChip(
                            avatar: Icon(_transitionIcon(transition), size: 17),
                            label: Text(_transitionLabel(transition)),
                            selected: clip.transition == transition,
                            onSelected: clip.locked
                                ? null
                                : (_) => onClipChanged(
                                    clip.copyWith(transition: transition),
                                  ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (clip.transition != TimelineTransition.cut)
                      _ValueControl(
                        icon: Icons.timelapse_outlined,
                        label: 'Duration',
                        value: clip.transitionDurationSeconds,
                        min: 0.1,
                        max: math.max(0.1, clip.durationSeconds / 2),
                        divisions: 30,
                        displayValue: _seconds(clip.transitionDurationSeconds),
                        onChanged: clip.locked
                            ? null
                            : (value) => onClipChanged(
                                clip.copyWith(transitionDurationSeconds: value),
                              ),
                      ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inspectorTab(List<Widget> children) {
    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(right: 22, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  Widget _clipSwitches() {
    return Column(
      children: [
        SwitchListTile(
          value: clip.enabled,
          onChanged: clip.locked
              ? null
              : (value) => onClipChanged(clip.copyWith(enabled: value)),
          title: const Text('Visible'),
          secondary: const Icon(Icons.visibility_outlined),
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          value: clip.locked,
          onChanged: (value) => onClipChanged(clip.copyWith(locked: value)),
          title: const Text('Locked'),
          secondary: const Icon(Icons.lock_outline),
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }

  String _transitionLabel(TimelineTransition transition) {
    return switch (transition) {
      TimelineTransition.cut => 'Precision cut',
      TimelineTransition.dissolve => 'Cross dissolve',
      TimelineTransition.fadeThroughBlack => 'Fade through black',
      TimelineTransition.slideLeft => 'Slide from right',
      TimelineTransition.slideRight => 'Slide from left',
      TimelineTransition.slideUp => 'Slide from bottom',
      TimelineTransition.slideDown => 'Slide from top',
      TimelineTransition.wipeLeft => 'Wipe left',
      TimelineTransition.wipeRight => 'Wipe right',
      TimelineTransition.wipeUp => 'Wipe up',
      TimelineTransition.wipeDown => 'Wipe down',
      TimelineTransition.zoomIn => 'Zoom in',
      TimelineTransition.zoomOut => 'Zoom out',
      TimelineTransition.circleOpen => 'Circle open',
      TimelineTransition.circleClose => 'Circle close',
      TimelineTransition.whipPan => 'Whip pan',
    };
  }

  IconData _transitionIcon(TimelineTransition transition) {
    return switch (transition) {
      TimelineTransition.cut => Icons.content_cut_outlined,
      TimelineTransition.dissolve => Icons.blur_on_outlined,
      TimelineTransition.fadeThroughBlack => Icons.brightness_2_outlined,
      TimelineTransition.slideLeft => Icons.keyboard_double_arrow_left,
      TimelineTransition.slideRight => Icons.keyboard_double_arrow_right,
      TimelineTransition.slideUp => Icons.keyboard_double_arrow_up,
      TimelineTransition.slideDown => Icons.keyboard_double_arrow_down,
      TimelineTransition.wipeLeft => Icons.keyboard_arrow_left,
      TimelineTransition.wipeRight => Icons.keyboard_arrow_right,
      TimelineTransition.wipeUp => Icons.keyboard_arrow_up,
      TimelineTransition.wipeDown => Icons.keyboard_arrow_down,
      TimelineTransition.zoomIn => Icons.zoom_in_outlined,
      TimelineTransition.zoomOut => Icons.zoom_out_outlined,
      TimelineTransition.circleOpen => Icons.circle_outlined,
      TimelineTransition.circleClose => Icons.circle,
      TimelineTransition.whipPan => Icons.blur_linear_outlined,
    };
  }

  String _animationLabel(ClipAnimationType type) {
    return switch (type) {
      ClipAnimationType.none => 'None',
      ClipAnimationType.kenBurnsIn => 'Ken Burns in',
      ClipAnimationType.kenBurnsOut => 'Ken Burns out',
      ClipAnimationType.zoomPunch => 'Zoom punch',
      ClipAnimationType.slideIn => 'Slide in',
      ClipAnimationType.popIn => 'Pop in',
      ClipAnimationType.fadeIn => 'Fade in',
      ClipAnimationType.fadeOut => 'Fade out',
    };
  }

  TimelineClip _applyGradePreset(TimelineClip clip, String preset) {
    return switch (preset) {
      'Enhanced' => clip.copyWith(
        brightness: -0.02,
        saturation: 1.22,
        contrast: 1.12,
        gamma: 1.02,
        sharpness: 0.55,
      ),
      'Vibrant' => clip.copyWith(
        brightness: -0.01,
        saturation: 1.38,
        contrast: 1.18,
        gamma: 1.03,
        sharpness: 0.65,
      ),
      'Dark' => clip.copyWith(
        brightness: -0.16,
        saturation: 1.12,
        contrast: 1.2,
        gamma: 0.96,
        sharpness: 0.5,
      ),
      'Cinematic' => clip.copyWith(
        brightness: -0.08,
        saturation: 0.92,
        contrast: 1.16,
        gamma: 0.98,
        sharpness: 0.45,
      ),
      _ => clip.copyWith(
        brightness: 0,
        saturation: 1,
        contrast: 1,
        gamma: 1,
        sharpness: 0,
      ),
    };
  }
}

class _InspectorPanel extends StatelessWidget {
  const _InspectorPanel({
    required this.clip,
    required this.timelineDuration,
    required this.onClipChanged,
  });

  final TimelineClip? clip;
  final double timelineDuration;
  final ValueChanged<TimelineClip> onClipChanged;

  @override
  Widget build(BuildContext context) {
    final clip = this.clip;
    final sourceDuration = math.max(clip?.sourceDurationSeconds ?? 3600.0, 0.1);
    return _EditorPanel(
      title: 'Inspector',
      child: clip == null
          ? const Center(
              child: Text(
                'Select a clip',
                style: TextStyle(color: Color(0xFF9A9A9A)),
              ),
            )
          : Scrollbar(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(right: 34, bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          clip.isVideo
                              ? Icons.movie_creation_outlined
                              : Icons.graphic_eq_outlined,
                          color: clip.isVideo
                              ? const Color(0xFF6F97A5)
                              : const Color(0xFF668C72),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            clip.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SegmentedButton<int>(
                      segments: [
                        for (var i = 0; i < 3; i++)
                          ButtonSegment(
                            value: i,
                            label: Text(
                              clip.isVideo ? 'V${i + 1}' : 'A${i + 1}',
                            ),
                          ),
                      ],
                      selected: {clip.trackIndex.clamp(0, 2).toInt()},
                      onSelectionChanged: clip.locked
                          ? null
                          : (selection) {
                              onClipChanged(
                                clip.copyWith(trackIndex: selection.first),
                              );
                            },
                    ),
                    const SizedBox(height: 14),
                    _ValueControl(
                      icon: Icons.start_outlined,
                      label: 'Timeline start',
                      value: clip.timelineStartSeconds,
                      min: 0,
                      max: math.max(
                        timelineDuration,
                        clip.timelineStartSeconds + 1,
                      ),
                      divisions: 200,
                      displayValue: _seconds(clip.timelineStartSeconds),
                      onChanged: clip.locked
                          ? null
                          : (value) {
                              onClipChanged(
                                clip.copyWith(timelineStartSeconds: value),
                              );
                            },
                    ),
                    _ValueControl(
                      icon: Icons.content_cut_outlined,
                      label: 'Trim in',
                      value: clip.trimStartSeconds,
                      min: 0,
                      max: math.max(
                        0.1,
                        math.min(
                          clip.trimEndSeconds - 0.1,
                          sourceDuration - 0.1,
                        ),
                      ),
                      divisions: 200,
                      displayValue: _seconds(clip.trimStartSeconds),
                      onChanged: clip.locked
                          ? null
                          : (value) {
                              onClipChanged(
                                clip.copyWith(trimStartSeconds: value),
                              );
                            },
                    ),
                    _ValueControl(
                      icon: Icons.flag_outlined,
                      label: 'Trim out',
                      value: clip.trimEndSeconds,
                      min: clip.trimStartSeconds + 0.1,
                      max: math.max(
                        clip.trimStartSeconds + 0.1,
                        sourceDuration,
                      ),
                      divisions: 300,
                      displayValue: _seconds(clip.trimEndSeconds),
                      onChanged: clip.locked
                          ? null
                          : (value) {
                              onClipChanged(
                                clip.copyWith(trimEndSeconds: value),
                              );
                            },
                    ),
                    if (clip.isVideo) ...[
                      _ValueControl(
                        icon: Icons.open_with_outlined,
                        label: 'Horizontal',
                        value: clip.x,
                        min: -1.5,
                        max: 1.5,
                        divisions: 120,
                        displayValue: _signed(clip.x),
                        onChanged: clip.locked
                            ? null
                            : (value) {
                                onClipChanged(clip.copyWith(x: value));
                              },
                      ),
                      _ValueControl(
                        icon: Icons.height_outlined,
                        label: 'Vertical',
                        value: clip.y,
                        min: -1.5,
                        max: 1.5,
                        divisions: 120,
                        displayValue: _signed(clip.y),
                        onChanged: clip.locked
                            ? null
                            : (value) {
                                onClipChanged(clip.copyWith(y: value));
                              },
                      ),
                      _ValueControl(
                        icon: Icons.zoom_out_map_outlined,
                        label: 'Scale',
                        value: clip.scale,
                        min: 0.1,
                        max: 3,
                        divisions: 145,
                        displayValue: '${(clip.scale * 100).round()}%',
                        onChanged: clip.locked
                            ? null
                            : (value) {
                                onClipChanged(clip.copyWith(scale: value));
                              },
                      ),
                      _ValueControl(
                        icon: Icons.opacity_outlined,
                        label: 'Opacity',
                        value: clip.opacity,
                        min: 0,
                        max: 1,
                        divisions: 100,
                        displayValue: '${(clip.opacity * 100).round()}%',
                        onChanged: clip.locked
                            ? null
                            : (value) {
                                onClipChanged(clip.copyWith(opacity: value));
                              },
                      ),
                    ],
                    if (clip.isAudio)
                      _ValueControl(
                        icon: Icons.volume_up_outlined,
                        label: 'Volume',
                        value: clip.volume,
                        min: 0,
                        max: 2,
                        divisions: 100,
                        displayValue: '${(clip.volume * 100).round()}%',
                        onChanged: clip.locked
                            ? null
                            : (value) {
                                onClipChanged(clip.copyWith(volume: value));
                              },
                      ),
                    if (clip.isAudio) ...[
                      _ValueControl(
                        icon: Icons.trending_up_outlined,
                        label: 'Fade in',
                        value: clip.audioFadeInSeconds,
                        min: 0,
                        max: clip.durationSeconds,
                        divisions: math.max(
                          1,
                          (clip.durationSeconds * 10).round(),
                        ),
                        displayValue: _seconds(clip.audioFadeInSeconds),
                        onChanged: clip.locked
                            ? null
                            : (value) {
                                onClipChanged(
                                  clip.copyWith(audioFadeInSeconds: value),
                                );
                              },
                      ),
                      _ValueControl(
                        icon: Icons.trending_down_outlined,
                        label: 'Fade out',
                        value: clip.audioFadeOutSeconds,
                        min: 0,
                        max: clip.durationSeconds,
                        divisions: math.max(
                          1,
                          (clip.durationSeconds * 10).round(),
                        ),
                        displayValue: _seconds(clip.audioFadeOutSeconds),
                        onChanged: clip.locked
                            ? null
                            : (value) {
                                onClipChanged(
                                  clip.copyWith(audioFadeOutSeconds: value),
                                );
                              },
                      ),
                    ],
                    SwitchListTile(
                      value: clip.enabled,
                      onChanged: clip.locked
                          ? null
                          : (value) {
                              onClipChanged(clip.copyWith(enabled: value));
                            },
                      title: Text(clip.isVideo ? 'Visible' : 'Enabled'),
                      secondary: Icon(
                        clip.isVideo
                            ? Icons.visibility_outlined
                            : Icons.power_settings_new_outlined,
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (clip.isAudio)
                      SwitchListTile(
                        value: clip.muted,
                        onChanged: clip.locked
                            ? null
                            : (value) {
                                onClipChanged(clip.copyWith(muted: value));
                              },
                        title: const Text('Muted'),
                        secondary: const Icon(Icons.volume_off_outlined),
                        contentPadding: EdgeInsets.zero,
                      ),
                    SwitchListTile(
                      value: clip.locked,
                      onChanged: (value) {
                        onClipChanged(clip.copyWith(locked: value));
                      },
                      title: const Text('Locked'),
                      secondary: const Icon(Icons.lock_outline),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _ValueControl extends StatelessWidget {
  const _ValueControl({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.displayValue,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String displayValue;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, size: 19, color: const Color(0xFFD0D0D0)),
              const SizedBox(width: 10),
              Expanded(child: Text(label)),
              Text(
                displayValue,
                style: const TextStyle(
                  color: Color(0xFFD0D0D0),
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _EditorPanel extends StatelessWidget {
  const _EditorPanel({
    required this.title,
    required this.child,
    this.actions = const [],
    this.expandChild = true,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;
  final bool expandChild;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF303030)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: expandChild ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: actions,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            if (expandChild) Expanded(child: child) else child,
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 16),
      label: Text(label),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF3A3A3A)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

String _seconds(double seconds) {
  final minutes = seconds ~/ 60;
  final remainingSeconds = seconds - minutes * 60;
  if (minutes == 0) {
    return '${remainingSeconds.toStringAsFixed(1)}s';
  }
  return '$minutes:${remainingSeconds.toStringAsFixed(1).padLeft(4, '0')}';
}

String _signed(double value) {
  final prefix = value >= 0 ? '+' : '';
  return '$prefix${value.toStringAsFixed(2)}';
}

List<double> _previewColorMatrix(TimelineClip clip) {
  const redLuminance = 0.213;
  const greenLuminance = 0.715;
  const blueLuminance = 0.072;
  final look = _previewLookAdjustments(clip);
  final saturation = (clip.saturation * look.saturation)
      .clamp(0.0, 3.0)
      .toDouble();
  final contrast = (clip.contrast * look.contrast).clamp(0.1, 3.0).toDouble();
  final inverseSaturation = 1 - saturation;
  final red = inverseSaturation * redLuminance;
  final green = inverseSaturation * greenLuminance;
  final blue = inverseSaturation * blueLuminance;
  final offset =
      (1 - contrast) * 128 + (clip.brightness + look.brightness) * 255;
  final temperature = clip.temperature * 18 + look.temperature;
  final tint = clip.tint * 14 + look.tint;
  final redOffset = offset + temperature;
  final greenOffset = offset + tint;
  final blueOffset = offset - temperature;

  return <double>[
    (red + saturation) * contrast,
    green * contrast,
    blue * contrast,
    0,
    redOffset,
    red * contrast,
    (green + saturation) * contrast,
    blue * contrast,
    0,
    greenOffset,
    red * contrast,
    green * contrast,
    (blue + saturation) * contrast,
    0,
    blueOffset,
    0,
    0,
    0,
    1,
    0,
  ];
}

({
  double saturation,
  double contrast,
  double brightness,
  double temperature,
  double tint,
})
_previewLookAdjustments(TimelineClip clip) {
  final intensity = clip.lutIntensity.clamp(0.0, 1.0).toDouble();
  return switch (clip.lutId) {
    'cinematic' => (
      saturation: 1 - 0.12 * intensity,
      contrast: 1 + 0.16 * intensity,
      brightness: -0.035 * intensity,
      temperature: -10 * intensity,
      tint: 4 * intensity,
    ),
    'retro' => (
      saturation: 1 + 0.12 * intensity,
      contrast: 1 - 0.08 * intensity,
      brightness: 0.025 * intensity,
      temperature: 18 * intensity,
      tint: 5 * intensity,
    ),
    'portrait' => (
      saturation: 1 + 0.06 * intensity,
      contrast: 1 + 0.06 * intensity,
      brightness: 0.018 * intensity,
      temperature: 10 * intensity,
      tint: 3 * intensity,
    ),
    'mono' => (
      saturation: 1 - 0.95 * intensity,
      contrast: 1 + 0.10 * intensity,
      brightness: 0,
      temperature: 0,
      tint: 0,
    ),
    'vlog' => (
      saturation: 1 + 0.16 * intensity,
      contrast: 1 + 0.05 * intensity,
      brightness: 0.02 * intensity,
      temperature: 6 * intensity,
      tint: 2 * intensity,
    ),
    _ => (saturation: 1, contrast: 1, brightness: 0, temperature: 0, tint: 0),
  };
}

bool _isVideoClipVisibleAt(
  TimelineClip clip,
  List<TimelineClip> clips,
  double playheadSeconds,
) {
  if (clip.isActiveAt(playheadSeconds)) {
    return true;
  }
  if (playheadSeconds < clip.timelineEndSeconds) {
    return false;
  }
  for (final incoming in clips) {
    if (!incoming.isVideo ||
        !incoming.enabled ||
        incoming.id == clip.id ||
        !_transitionKeepsOutgoingVisible(incoming.transition) ||
        (incoming.timelineStartSeconds - clip.timelineEndSeconds).abs() >
            0.08) {
      continue;
    }
    return playheadSeconds <=
        incoming.timelineStartSeconds + incoming.transitionDurationSeconds;
  }
  return false;
}

bool _transitionKeepsOutgoingVisible(TimelineTransition transition) {
  return transition == TimelineTransition.dissolve ||
      transition == TimelineTransition.slideLeft ||
      transition == TimelineTransition.slideRight ||
      transition == TimelineTransition.slideUp ||
      transition == TimelineTransition.slideDown ||
      transition == TimelineTransition.wipeLeft ||
      transition == TimelineTransition.wipeRight ||
      transition == TimelineTransition.wipeUp ||
      transition == TimelineTransition.wipeDown ||
      transition == TimelineTransition.whipPan;
}

void _prioritizeActiveTransition(
  List<TimelineClip> clips,
  double playheadSeconds,
) {
  for (var i = clips.length - 1; i >= 0; i--) {
    final clip = clips[i];
    if (clip.transition == TimelineTransition.cut ||
        playheadSeconds < clip.timelineStartSeconds ||
        playheadSeconds >
            clip.timelineStartSeconds + clip.transitionDurationSeconds) {
      continue;
    }
    clips
      ..removeAt(i)
      ..add(clip);
    return;
  }
}

String _transitionName(TimelineTransition transition) {
  return switch (transition) {
    TimelineTransition.cut => 'Precision Cut',
    TimelineTransition.dissolve => 'Cross Dissolve',
    TimelineTransition.fadeThroughBlack => 'Fade Through Black',
    TimelineTransition.slideLeft => 'Slide From Right',
    TimelineTransition.slideRight => 'Slide From Left',
    TimelineTransition.slideUp => 'Slide From Bottom',
    TimelineTransition.slideDown => 'Slide From Top',
    TimelineTransition.wipeLeft => 'Wipe Left',
    TimelineTransition.wipeRight => 'Wipe Right',
    TimelineTransition.wipeUp => 'Wipe Up',
    TimelineTransition.wipeDown => 'Wipe Down',
    TimelineTransition.zoomIn => 'Zoom In',
    TimelineTransition.zoomOut => 'Zoom Out',
    TimelineTransition.circleOpen => 'Circle Open',
    TimelineTransition.circleClose => 'Circle Close',
    TimelineTransition.whipPan => 'Whip Pan',
  };
}

IconData _transitionIconData(TimelineTransition transition) {
  return switch (transition) {
    TimelineTransition.cut => Icons.content_cut_outlined,
    TimelineTransition.dissolve => Icons.blur_on_outlined,
    TimelineTransition.fadeThroughBlack => Icons.brightness_2_outlined,
    TimelineTransition.slideLeft => Icons.keyboard_double_arrow_left,
    TimelineTransition.slideRight => Icons.keyboard_double_arrow_right,
    TimelineTransition.slideUp => Icons.keyboard_double_arrow_up,
    TimelineTransition.slideDown => Icons.keyboard_double_arrow_down,
    TimelineTransition.wipeLeft => Icons.keyboard_arrow_left,
    TimelineTransition.wipeRight => Icons.keyboard_arrow_right,
    TimelineTransition.wipeUp => Icons.keyboard_arrow_up,
    TimelineTransition.wipeDown => Icons.keyboard_arrow_down,
    TimelineTransition.zoomIn => Icons.zoom_in_outlined,
    TimelineTransition.zoomOut => Icons.zoom_out_outlined,
    TimelineTransition.circleOpen => Icons.circle_outlined,
    TimelineTransition.circleClose => Icons.circle,
    TimelineTransition.whipPan => Icons.blur_linear_outlined,
  };
}

String _ffmpegNumber(num value) {
  final text = value.toStringAsFixed(3);
  return text.replaceFirst(RegExp(r'\.?0+$'), '');
}
