import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../infrastructure/ffmpeg/ffmpeg_executables.dart';

/// Extracts complete JPEG images from a raw MJPEG byte stream.
class MjpegFrameParser {
  static const _jpegStart = [0xFF, 0xD8];
  static const _jpegEnd = [0xFF, 0xD9];

  final List<int> _buffer = [];

  /// Feeds a chunk and returns every complete frame found so far.
  List<Uint8List> feed(List<int> chunk) {
    _buffer.addAll(chunk);
    final frames = <Uint8List>[];
    while (true) {
      final start = _findMarker(_buffer, _jpegStart, 0);
      if (start == -1) {
        if (_buffer.length > 4096) {
          _buffer.removeRange(0, _buffer.length - 2);
        }
        return frames;
      }
      final end = _findMarker(_buffer, _jpegEnd, start + 2);
      if (end == -1) {
        if (start > 0) {
          _buffer.removeRange(0, start);
        }
        return frames;
      }
      frames.add(Uint8List.fromList(_buffer.sublist(start, end + 2)));
      _buffer.removeRange(0, end + 2);
    }
  }

  void reset() => _buffer.clear();

  static int _findMarker(List<int> bytes, List<int> marker, int start) {
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
}

/// Streams decoded video frames from FFmpeg at a steady, wall-clock-locked
/// frame rate.
///
/// FFmpeg decodes as fast as the pipe allows; a bounded frame queue with
/// subscription backpressure acts as a jitter buffer, and a display timer
/// paces delivery so playback stays smooth even when the pipe is bursty.
/// The pacer consumes frames according to elapsed *wall time*, so if the UI
/// stalls it catches up by dropping frames instead of drifting out of sync
/// with audio.
///
/// Frames are decoded to [ui.Image] via the engine's image codec (off the UI
/// thread) and handed to [onFrame]; the receiver owns each image and must
/// dispose it.
class FrameStreamPlayer {
  FrameStreamPlayer({required this.onFrame});

  /// Called with each decoded frame, paced at the requested display rate.
  final void Function(ui.Image image) onFrame;

  static const int _maxQueuedFrames = 24;
  static const int _resumeThreshold = 12;

  /// Frame budget for one buffered reverse segment (~10s at 30fps). Reverse
  /// playback must buffer a whole segment before it can show the last frame
  /// first, so this bounds both memory and the startup delay.
  static const int _reverseSegmentFrames = 300;

  final MjpegFrameParser _parser = MjpegFrameParser();
  final List<Uint8List> _queue = [];

  Process? _process;
  StreamSubscription<List<int>>? _subscription;
  Timer? _displayTimer;
  bool _subscriptionPaused = false;
  bool _decoding = false;
  bool _playbackStarted = false;
  int _generation = 0;

  // Wall-clock pacing state.
  DateTime? _paceStartedAt;
  int _framesConsumed = 0;
  double _displayFps = 30;

  // Reverse-playback state.
  bool _reverse = false;
  bool _reverseSegmentComplete = false;
  double _reverseSegmentStartSeconds = 0;
  double _reverseFloorSeconds = 0;
  String _reverseInputPath = '';
  double _reverseSpeed = 1;
  int _reverseMaxDimension = 960;

  bool get isActive => _process != null || _displayTimer != null;

  /// Plays [inputPath] forward from [startSeconds] (source time) at
  /// [displayFps], optionally speed-adjusted and clipped to
  /// [sourceDurationSeconds] of source material.
  Future<void> playForward({
    required String inputPath,
    required double startSeconds,
    required double displayFps,
    double? sourceDurationSeconds,
    double speed = 1,
    int maxDimension = 960,
    bool preload = false,
  }) async {
    stop();
    final generation = _generation;
    _reverse = false;
    _displayFps = displayFps;

    try {
      final process = await Process.start(FfmpegExecutables.ffmpeg, <String>[
        '-hide_banner',
        '-loglevel',
        'error',
        '-ss',
        _number(startSeconds),
        '-i',
        inputPath,
        if (sourceDurationSeconds != null) ...[
          '-t',
          _number(sourceDurationSeconds),
        ],
        '-vf',
        _videoFilter(speed: speed, fps: displayFps, maxDimension: maxDimension),
        '-an',
        '-f',
        'image2pipe',
        '-vcodec',
        'mjpeg',
        '-q:v',
        '4',
        'pipe:1',
      ]);
      if (generation != _generation) {
        process.kill();
        return;
      }
      _attachProcess(process, generation);
      if (!preload) {
        startPlayback();
      } else if (_playbackStarted) {
        _startDisplayTimer(generation);
      }
    } catch (_) {
      return;
    }
  }

  /// Starts a stream that was opened with [preload] enabled.
  ///
  /// Preloading lets FFmpeg decode into the bounded queue before a timeline
  /// cut. At the cut, playback begins from the already-buffered first frame
  /// instead of waiting for a new process and decoder to start.
  void startPlayback() {
    if (_playbackStarted) {
      return;
    }
    _playbackStarted = true;
    if ((_process != null || _queue.isNotEmpty) &&
        (!_reverse || _reverseSegmentComplete)) {
      _startDisplayTimer(_generation);
    }
  }

  /// Plays [inputPath] backwards starting from [endSeconds] (source time)
  /// down to [floorSeconds]. The segment before [endSeconds] is decoded
  /// forward into a compressed frame buffer, then displayed in reverse;
  /// earlier segments are chained automatically.
  Future<void> playReverse({
    required String inputPath,
    required double endSeconds,
    required double floorSeconds,
    required double displayFps,
    double speed = 1,
    int maxDimension = 960,
    bool preload = false,
  }) async {
    stop();
    _reverse = true;
    _playbackStarted = !preload;
    _displayFps = displayFps;
    _reverseFloorSeconds = floorSeconds;
    _reverseInputPath = inputPath;
    _reverseSpeed = speed;
    _reverseMaxDimension = maxDimension;
    await _startReverseSegment(endSeconds, _generation);
  }

  Future<void> _startReverseSegment(double endSeconds, int generation) async {
    // How much source time one buffered segment covers after speed-up.
    final segmentSourceSeconds =
        _reverseSegmentFrames / _displayFps * _reverseSpeed;
    final segmentStart = math.max(
      _reverseFloorSeconds,
      endSeconds - segmentSourceSeconds,
    );
    final segmentDuration = endSeconds - segmentStart;
    if (segmentDuration <= 0.01) {
      return;
    }
    _reverseSegmentStartSeconds = segmentStart;
    _reverseSegmentComplete = false;

    try {
      final process = await Process.start(FfmpegExecutables.ffmpeg, <String>[
        '-hide_banner',
        '-loglevel',
        'error',
        '-ss',
        _number(segmentStart),
        '-i',
        _reverseInputPath,
        '-t',
        _number(segmentDuration),
        '-vf',
        _videoFilter(
          speed: _reverseSpeed,
          fps: _displayFps,
          maxDimension: _reverseMaxDimension,
        ),
        '-an',
        '-f',
        'image2pipe',
        '-vcodec',
        'mjpeg',
        '-q:v',
        '4',
        'pipe:1',
      ]);
      if (generation != _generation) {
        process.kill();
        return;
      }
      _process = process;
      _parser.reset();
      // Reverse segments buffer fully (compressed JPEGs) before playback —
      // the last decoded frame has to be shown first.
      _subscription = process.stdout.listen((chunk) {
        if (generation != _generation) {
          return;
        }
        _queue.addAll(_parser.feed(chunk));
        // Safety valve: never hold more than two segments' worth.
        while (_queue.length > _reverseSegmentFrames * 2) {
          _queue.removeAt(0);
        }
      }, onError: (_) {});
      unawaited(process.stderr.drain<void>());
      unawaited(
        process.exitCode.then((_) {
          if (generation != _generation) {
            return;
          }
          _reverseSegmentComplete = true;
          if (identical(_process, process)) {
            _process = null;
          }
          if (_playbackStarted) {
            _startDisplayTimer(generation);
          }
        }),
      );
    } catch (_) {
      return;
    }
  }

  void _attachProcess(Process process, int generation) {
    _process = process;
    _parser.reset();
    _subscription = process.stdout.listen(
      (chunk) {
        if (generation != _generation) {
          return;
        }
        _queue.addAll(_parser.feed(chunk));
        if (_queue.length >= _maxQueuedFrames && !_subscriptionPaused) {
          _subscription?.pause();
          _subscriptionPaused = true;
        }
      },
      onError: (_) {},
      onDone: () {
        if (generation == _generation && identical(_process, process)) {
          _process = null;
        }
      },
    );
    unawaited(process.stderr.drain<void>());
    unawaited(
      process.exitCode.then((_) {
        if (generation == _generation && identical(_process, process)) {
          _process = null;
        }
      }),
    );
  }

  void _startDisplayTimer(int generation) {
    _displayTimer?.cancel();
    // The pace clock starts when the first frame arrives (see _onDisplayTick)
    // so seek/startup latency isn't misread as the UI falling behind.
    _paceStartedAt = null;
    _framesConsumed = 0;
    final tickInterval = Duration(
      microseconds: math.max(1, (1000000 / _displayFps).round()),
    );
    _displayTimer = Timer.periodic(tickInterval, (_) {
      if (generation != _generation) {
        return;
      }
      _onDisplayTick(generation);
    });
    _onDisplayTick(generation);
  }

  void _onDisplayTick(int generation) {
    if (_queue.isEmpty) {
      _maybeFinishReverseSegment(generation);
      return;
    }
    final startedAt = _paceStartedAt ??= DateTime.now();

    // Wall-clock lock: consume however many frames elapsed time demands,
    // decoding only the newest so a slow UI drops frames instead of lagging.
    final elapsedSeconds =
        DateTime.now().difference(startedAt).inMicroseconds / 1000000;
    final targetConsumed = (elapsedSeconds * _displayFps).floor() + 1;
    var toConsume = targetConsumed - _framesConsumed;
    if (toConsume <= 0) {
      return;
    }
    toConsume = math.min(toConsume, _queue.length);

    Uint8List? bytes;
    for (var i = 0; i < toConsume; i++) {
      bytes = _reverse ? _queue.removeLast() : _queue.removeAt(0);
    }
    _framesConsumed += toConsume;
    if (_subscriptionPaused && _queue.length <= _resumeThreshold) {
      _subscription?.resume();
      _subscriptionPaused = false;
    }
    _maybeFinishReverseSegment(generation);

    if (bytes == null || _decoding) {
      return;
    }
    _decoding = true;
    unawaited(_decodeAndEmit(bytes, generation));
  }

  Future<void> _decodeAndEmit(Uint8List bytes, int generation) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (generation != _generation) {
        frame.image.dispose();
        return;
      }
      _decoding = false;
      onFrame(frame.image);
    } catch (_) {
      if (generation == _generation) {
        _decoding = false;
      }
    }
  }

  void _maybeFinishReverseSegment(int generation) {
    if (!_reverse || !_reverseSegmentComplete || _queue.isNotEmpty) {
      return;
    }
    _reverseSegmentComplete = false;
    if (_reverseSegmentStartSeconds > _reverseFloorSeconds + 0.01) {
      unawaited(_startReverseSegment(_reverseSegmentStartSeconds, generation));
    } else {
      _displayTimer?.cancel();
      _displayTimer = null;
    }
  }

  /// Stops playback and discards buffered frames. In-flight decodes are
  /// invalidated via a generation counter.
  void stop() {
    _generation++;
    _displayTimer?.cancel();
    _displayTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _subscriptionPaused = false;
    _process?.kill();
    _process = null;
    _queue.clear();
    _parser.reset();
    _decoding = false;
    _playbackStarted = false;
    _paceStartedAt = null;
    _framesConsumed = 0;
    _reverseSegmentComplete = false;
  }

  void dispose() => stop();

  String _videoFilter({
    required double speed,
    required double fps,
    required int maxDimension,
  }) {
    final parts = <String>[
      if ((speed - 1).abs() > 0.001) 'setpts=(PTS-STARTPTS)/${_number(speed)}',
      'fps=${_number(fps)}',
      // Fit inside a maxDimension box without upscaling, then crop to even
      // dimensions for the MJPEG encoder.
      'scale=min($maxDimension\\,iw):min($maxDimension\\,ih)'
          ':force_original_aspect_ratio=decrease:flags=bilinear',
      'crop=trunc(iw/2)*2:trunc(ih/2)*2',
    ];
    return parts.join(',');
  }

  static String _number(num value) {
    final text = value.toStringAsFixed(3);
    return text.replaceFirst(RegExp(r'\.?0+$'), '');
  }
}
