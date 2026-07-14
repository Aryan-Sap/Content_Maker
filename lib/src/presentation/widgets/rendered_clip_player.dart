import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../domain/rendering/media_metadata.dart';
import '../../infrastructure/ffmpeg/ffmpeg_executables.dart';
import '../../infrastructure/ffmpeg/ffmpeg_media_probe.dart';

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
  static const _jpegStart = [0xFF, 0xD8];
  static const _jpegEnd = [0xFF, 0xD9];

  final _probe = const FfmpegMediaProbe();

  MediaMetadata? _metadata;
  Uint8List? _frameBytes;
  Process? _videoProcess;
  Process? _audioProcess;
  Timer? _positionTimer;
  final List<int> _streamBuffer = [];

  double _positionSeconds = 0;
  bool _isPlaying = false;
  bool _isScrubbing = false;
  DateTime? _playStartedAt;
  double _playStartPosition = 0;
  int _stillFrameRequest = 0;

  double get _durationSeconds => _metadata?.durationSeconds ?? 0;

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
      _positionSeconds = 0;
      _frameBytes = null;
      _metadata = null;
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _stopPlayback(updateState: false);
    super.dispose();
  }

  Future<void> _load() async {
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
      setState(() => _frameBytes = Uint8List.fromList(bytes));
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
    setState(() => _isPlaying = true);
    _playStartedAt = DateTime.now();
    _playStartPosition = _positionSeconds;
    await _startVideoStream(_positionSeconds);
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

  Future<void> _startVideoStream(double fromSeconds) async {
    _stopVideoStream();
    try {
      final process = await Process.start(FfmpegExecutables.ffmpeg, <String>[
        '-hide_banner',
        '-loglevel',
        'error',
        '-readrate',
        '1',
        '-ss',
        _number(fromSeconds),
        '-i',
        widget.videoPath,
        '-vf',
        'fps=30,scale=w=min(iw\\,1280):h=-2:flags=lanczos',
        '-an',
        '-f',
        'image2pipe',
        '-vcodec',
        'mjpeg',
        '-q:v',
        '3',
        'pipe:1',
      ]);
      if (!mounted || !_isPlaying) {
        process.kill();
        return;
      }
      _videoProcess = process;
      _streamBuffer.clear();
      process.stdout.listen(_handleStreamChunk, onError: (_) {});
      unawaited(process.stderr.drain<void>());
    } catch (_) {
      return;
    }
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

  void _handleStreamChunk(List<int> chunk) {
    if (!mounted || !_isPlaying) {
      return;
    }
    _streamBuffer.addAll(chunk);
    while (true) {
      final start = _findMarker(_streamBuffer, _jpegStart, 0);
      if (start == -1) {
        if (_streamBuffer.length > 4096) {
          _streamBuffer.removeRange(0, _streamBuffer.length - 2);
        }
        return;
      }
      final end = _findMarker(_streamBuffer, _jpegEnd, start + 2);
      if (end == -1) {
        if (start > 0) {
          _streamBuffer.removeRange(0, start);
        }
        return;
      }
      final frame = Uint8List.fromList(_streamBuffer.sublist(start, end + 2));
      _streamBuffer.removeRange(0, end + 2);
      setState(() => _frameBytes = frame);
    }
  }

  void _stopVideoStream() {
    final process = _videoProcess;
    _videoProcess = null;
    _streamBuffer.clear();
    process?.kill();
  }

  void _stopPlayback({bool updateState = true, bool resetToEnd = false}) {
    _positionTimer?.cancel();
    _positionTimer = null;
    _playStartedAt = null;
    _stopVideoStream();
    _audioProcess?.kill();
    _audioProcess = null;
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
    if (wasPlaying) {
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
    final frameBytes = _frameBytes;

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
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: ColoredBox(
                  color: Colors.black,
                  child: frameBytes == null
                      ? const Center(
                          child: Icon(
                            Icons.movie_outlined,
                            size: 44,
                            color: Color(0x66FFFFFF),
                          ),
                        )
                      : Image.memory(
                          frameBytes,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
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
                _isPlaying
                    ? Icons.pause_outlined
                    : Icons.play_arrow_outlined,
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

int _findMarker(List<int> bytes, List<int> marker, int start) {
  for (var i = start; i <= bytes.length - marker.length; i++) {
    var matches = true;
    for (var j = 0; j < marker.length; j++) {
      if (bytes[i + j] != marker[j]) {
        matches = false;
        break;
      }
    }
    if (matches) {
      return i;
    }
  }
  return -1;
}
