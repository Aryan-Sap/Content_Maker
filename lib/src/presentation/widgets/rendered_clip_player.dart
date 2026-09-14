import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

import '../../domain/rendering/media_metadata.dart';
import '../../infrastructure/ffmpeg/ffmpeg_executables.dart';
import '../../infrastructure/ffmpeg/ffmpeg_media_probe.dart';
import 'frame_stream_player.dart';

/// In-app player for a finished render: streams decoded frames from FFmpeg
/// (MJPEG over a pipe) with synced audio via ffplay, so the exported clip can
/// be reviewed inside the app before it is published anywhere.
class RenderedClipPlayer extends StatefulWidget {
  const RenderedClipPlayer({super.key, required this.videoPath});

  final String videoPath;

  @override
  State<RenderedClipPlayer> createState() => _RenderedClipPlayerState();
}

class _RenderedClipPlayerState extends State<RenderedClipPlayer> {
  final _probe = const FfmpegMediaProbe();

  MediaMetadata? _metadata;
  ui.Image? _currentImage;
  ui.Image? _previousImage;
  late final FrameStreamPlayer _videoPlayer = FrameStreamPlayer(
    onFrame: _handleFrame,
  );
  Process? _audioProcess;
  Timer? _positionTimer;
  VideoPlayerController? _nativeController;

  double _positionSeconds = 0;
  bool _isPlaying = false;
  bool _isScrubbing = false;
  DateTime? _playStartedAt;
  double _playStartPosition = 0;
  int _stillFrameRequest = 0;
  int _nativeLoadRequest = 0;

  bool get _usesNativePlayer => Platform.isAndroid || Platform.isIOS;

  double get _durationSeconds {
    final nativeController = _nativeController;
    if (nativeController != null) {
      return nativeController.value.duration.inMilliseconds / 1000;
    }
    return _metadata?.durationSeconds ?? 0;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant RenderedClipPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoPath != widget.videoPath) {
      _stopPlayback();
      final oldController = _nativeController;
      _nativeController = null;
      if (oldController != null) unawaited(oldController.dispose());
      _positionSeconds = 0;
      _clearImages();
      _metadata = null;
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _nativeLoadRequest++;
    _stopPlayback(updateState: false);
    _nativeController?.removeListener(_handleNativePlayerUpdate);
    final nativeController = _nativeController;
    if (nativeController != null) unawaited(nativeController.dispose());
    _videoPlayer.dispose();
    _previousImage?.dispose();
    _currentImage?.dispose();
    super.dispose();
  }

  void _handleFrame(ui.Image image) {
    if (!mounted) {
      image.dispose();
      return;
    }
    setState(() {
      _previousImage?.dispose();
      _previousImage = _currentImage;
      _currentImage = image;
    });
  }

  void _setStillImage(ui.Image image) {
    if (!mounted) {
      image.dispose();
      return;
    }
    setState(() {
      _previousImage?.dispose();
      _previousImage = null;
      final old = _currentImage;
      _currentImage = image;
      if (old != null) {
        SchedulerBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
    });
  }

  void _clearImages() {
    _previousImage?.dispose();
    _previousImage = null;
    final image = _currentImage;
    _currentImage = null;
    if (image != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) => image.dispose());
    }
  }

  Future<void> _load() async {
    if (_usesNativePlayer) {
      await _loadNativePlayer();
      return;
    }
    try {
      final metadata = await _probe.probe(widget.videoPath);
      if (!mounted) {
        return;
      }
      setState(() => _metadata = metadata);
      await _showStillFrame(0);
    } catch (_) {
      // Leave the placeholder; playback controls stay disabled.
    }
  }

  Future<void> _loadNativePlayer() async {
    final request = ++_nativeLoadRequest;
    final controller = VideoPlayerController.file(File(widget.videoPath));
    try {
      await controller.initialize();
      if (!mounted || request != _nativeLoadRequest) {
        await controller.dispose();
        return;
      }
      controller.addListener(_handleNativePlayerUpdate);
      setState(() {
        _nativeController = controller;
        _metadata = MediaMetadata(
          path: widget.videoPath,
          durationSeconds: controller.value.duration.inMilliseconds / 1000,
          width: controller.value.size.width.round(),
          height: controller.value.size.height.round(),
          hasAudio: true,
        );
      });
    } catch (_) {
      await controller.dispose();
    }
  }

  void _handleNativePlayerUpdate() {
    final controller = _nativeController;
    if (!mounted || controller == null) return;
    final value = controller.value;
    final nextPosition = value.position.inMilliseconds / 1000;
    if ((nextPosition - _positionSeconds).abs() >= 0.05 ||
        value.isPlaying != _isPlaying) {
      setState(() {
        _positionSeconds = nextPosition.clamp(0.0, _durationSeconds);
        _isPlaying = value.isPlaying;
      });
    }
  }

  Future<void> _showStillFrame(double seconds) async {
    final request = ++_stillFrameRequest;
    try {
      final result = await Process.run(FfmpegExecutables.ffmpeg, <String>[
        '-hide_banner',
        '-loglevel',
        'error',
        '-ss',
        _number(seconds),
        '-i',
        widget.videoPath,
        '-frames:v',
        '1',
        '-vf',
        'scale=w=min(iw\\,1280):h=-2:flags=lanczos',
        '-q:v',
        '3',
        '-f',
        'image2pipe',
        '-vcodec',
        'mjpeg',
        'pipe:1',
      ], stdoutEncoding: null);
      final bytes = result.stdout;
      if (!mounted ||
          request != _stillFrameRequest ||
          _isPlaying ||
          bytes is! List<int> ||
          bytes.isEmpty) {
        return;
      }
      final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted || request != _stillFrameRequest || _isPlaying) {
        frame.image.dispose();
        return;
      }
      _setStillImage(frame.image);
    } catch (_) {
      return;
    }
  }

  Future<void> _play() async {
    if (_isPlaying || _durationSeconds <= 0) {
      return;
    }
    if (_positionSeconds >= _durationSeconds - 0.05) {
      _positionSeconds = 0;
    }
    final nativeController = _nativeController;
    if (_usesNativePlayer && nativeController != null) {
      await nativeController.seekTo(
        Duration(milliseconds: (_positionSeconds * 1000).round()),
      );
      await nativeController.play();
      if (mounted) setState(() => _isPlaying = true);
      return;
    }
    setState(() => _isPlaying = true);
    _playStartedAt = DateTime.now();
    _playStartPosition = _positionSeconds;
    await _videoPlayer.playForward(
      inputPath: widget.videoPath,
      startSeconds: _positionSeconds,
      displayFps: 30,
      maxDimension: 1280,
    );
    _startAudio(_positionSeconds);
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final startedAt = _playStartedAt;
      if (!mounted || startedAt == null) {
        return;
      }
      final elapsed =
          DateTime.now().difference(startedAt).inMilliseconds / 1000;
      final next = _playStartPosition + elapsed;
      if (next >= _durationSeconds) {
        _stopPlayback(resetToEnd: true);
        return;
      }
      if (!_isScrubbing) {
        setState(() => _positionSeconds = next);
      }
    });
  }

  void _startAudio(double fromSeconds) {
    if (!(_metadata?.hasAudio ?? false)) {
      return;
    }
    unawaited(() async {
      try {
        final process = await Process.start(FfmpegExecutables.ffplay, <String>[
          '-nodisp',
          '-autoexit',
          '-loglevel',
          'quiet',
          '-ss',
          _number(fromSeconds),
          widget.videoPath,
        ]);
        if (!mounted || !_isPlaying) {
          process.kill();
          return;
        }
        _audioProcess = process;
      } catch (_) {
        return;
      }
    }());
  }

  void _stopPlayback({bool updateState = true, bool resetToEnd = false}) {
    _positionTimer?.cancel();
    _positionTimer = null;
    _playStartedAt = null;
    _videoPlayer.stop();
    _audioProcess?.kill();
    _audioProcess = null;
    final nativeController = _nativeController;
    if (_usesNativePlayer && nativeController != null) {
      unawaited(nativeController.pause());
    }
    if (!updateState || !mounted) {
      _isPlaying = false;
      return;
    }
    setState(() {
      _isPlaying = false;
      if (resetToEnd) {
        _positionSeconds = _durationSeconds;
      }
    });
  }

  void _togglePlayback() {
    if (_isPlaying) {
      _stopPlayback();
      unawaited(_showStillFrame(_positionSeconds));
    } else {
      unawaited(_play());
    }
  }

  void _seek(double seconds) {
    final wasPlaying = _isPlaying;
    _stopPlayback();
    setState(
      () => _positionSeconds = seconds.clamp(0.0, _durationSeconds).toDouble(),
    );
    final nativeController = _nativeController;
    if (_usesNativePlayer && nativeController != null) {
      unawaited(() async {
        await nativeController.seekTo(
          Duration(milliseconds: (_positionSeconds * 1000).round()),
        );
        if (wasPlaying) await nativeController.play();
      }());
    } else if (wasPlaying) {
      unawaited(_play());
    } else {
      unawaited(_showStillFrame(_positionSeconds));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metadata = _metadata;
    final aspectRatio =
        (metadata?.width ?? 0) > 0 && (metadata?.height ?? 0) > 0
        ? metadata!.width! / metadata.height!
        : 9 / 16;
    final currentImage = _currentImage;
    final nativeController = _nativeController;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.preview_outlined),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Preview render — ${p.basename(widget.videoPath)}',
                style: theme.textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 480),
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: ClipRect(
                child: ColoredBox(
                  color: Colors.black,
                  child:
                      _usesNativePlayer &&
                          nativeController?.value.isInitialized == true
                      ? VideoPlayer(nativeController!)
                      : currentImage == null
                      ? const Center(
                          child: Icon(
                            Icons.movie_outlined,
                            size: 44,
                            color: Color(0x66FFFFFF),
                          ),
                        )
                      : RawImage(
                          image: currentImage,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium,
                          isAntiAlias: true,
                        ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton.filledTonal(
              tooltip: _isPlaying ? 'Pause' : 'Play',
              onPressed: _durationSeconds > 0 ? _togglePlayback : null,
              icon: Icon(
                _isPlaying ? Icons.pause_outlined : Icons.play_arrow_outlined,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _formatTime(_positionSeconds),
              style: theme.textTheme.bodySmall,
            ),
            Expanded(
              child: Slider(
                value: _durationSeconds <= 0
                    ? 0
                    : _positionSeconds.clamp(0.0, _durationSeconds).toDouble(),
                max: _durationSeconds <= 0 ? 1 : _durationSeconds,
                onChangeStart: (_) => _isScrubbing = true,
                onChanged: _durationSeconds <= 0
                    ? null
                    : (value) => setState(() => _positionSeconds = value),
                onChangeEnd: (value) {
                  _isScrubbing = false;
                  _seek(value);
                },
              ),
            ),
            Text(
              _formatTime(_durationSeconds),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ],
    );
  }
}

String _formatTime(double seconds) {
  final safeSeconds = seconds.isFinite && seconds > 0 ? seconds : 0;
  final minutes = safeSeconds ~/ 60;
  final secs = (safeSeconds % 60).floor();
  return '$minutes:${secs.toString().padLeft(2, '0')}';
}

String _number(num value) {
  final text = value.toStringAsFixed(3);
  return text.replaceFirst(RegExp(r'\.?0+$'), '');
}
