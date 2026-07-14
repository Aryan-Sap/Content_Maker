import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../domain/rendering/media_metadata.dart';
import 'ffmpeg_executables.dart';

class FfmpegMediaProbe implements MediaProbe {
  const FfmpegMediaProbe();

  static final Map<String, Future<MediaMetadata>> _cache = {};

  @override
  Future<MediaMetadata> probe(String path) {
    final normalizedPath = path.trim();
    return _cache.putIfAbsent(normalizedPath, () => _probe(normalizedPath));
  }

  Future<MediaMetadata> _probe(String path) async {
    final result = await Process.run(FfmpegExecutables.ffprobe, <String>[
      '-v',
      'error',
      '-print_format',
      'json',
      '-show_format',
      '-show_streams',
      path,
    ]).timeout(const Duration(seconds: 10));

    if (result.exitCode != 0) {
      throw StateError(_failureMessage('ffprobe', result.stderr));
    }

    final decoded = jsonDecode('${result.stdout}') as Map<String, dynamic>;
    final streams = (decoded['streams'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final format = decoded['format'] as Map<String, dynamic>?;
    final videoStream = streams.cast<Map<String, dynamic>?>().firstWhere(
      (stream) => stream?['codec_type'] == 'video',
      orElse: () => null,
    );
    final hasAudio = streams.any((stream) => stream['codec_type'] == 'audio');

    return MediaMetadata(
      path: path,
      durationSeconds:
          _parseDouble(format?['duration']) ??
          _parseDouble(videoStream?['duration']),
      frameRate:
          _parseFrameRate(videoStream?['avg_frame_rate']) ??
          _parseFrameRate(videoStream?['r_frame_rate']),
      width: _parseInt(videoStream?['width']),
      height: _parseInt(videoStream?['height']),
      sampleAspectRatio: _parseSar(videoStream?['sample_aspect_ratio']),
      hasAudio: hasAudio,
    );
  }

  static double? _parseDouble(Object? value) {
    if (value == null) {
      return null;
    }
    return double.tryParse('$value');
  }

  static int? _parseInt(Object? value) {
    if (value == null) {
      return null;
    }
    return int.tryParse('$value');
  }

  static String? _parseSar(Object? value) {
    final text = '$value'.trim();
    if (text.isEmpty || text == 'null' || text == 'N/A') {
      return null;
    }
    return text;
  }

  static double? _parseFrameRate(Object? value) {
    final text = '$value'.trim();
    if (text.isEmpty || text == 'null' || text == '0/0') {
      return null;
    }

    final parts = text.split('/');
    if (parts.length == 2) {
      final numerator = double.tryParse(parts[0]);
      final denominator = double.tryParse(parts[1]);
      if (numerator == null || denominator == null || denominator == 0) {
        return null;
      }
      return numerator / denominator;
    }

    return double.tryParse(text);
  }

  static String _failureMessage(String tool, Object stderr) {
    final lines = '$stderr'
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      return '$tool failed without details.';
    }

    return lines.length > 5
        ? lines.sublist(lines.length - 5).join('\n')
        : lines.join('\n');
  }
}
