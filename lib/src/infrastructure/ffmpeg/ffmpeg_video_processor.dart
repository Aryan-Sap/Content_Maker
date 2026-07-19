import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/rendering/media_metadata.dart';
import '../../domain/rendering/render_job.dart';
import '../../domain/rendering/video_processor.dart';
import 'ffmpeg_command_builder.dart';
import 'ffmpeg_executables.dart';
import 'ffmpeg_media_probe.dart';
import 'ffmpeg_tool_validator.dart';

class FfmpegVideoProcessor implements VideoProcessor {
  const FfmpegVideoProcessor({
    this.commandBuilder = const FfmpegCommandBuilder(),
    this.mediaProbe = const FfmpegMediaProbe(),
    this.toolValidator = const FfmpegToolValidator(),
  });

  final FfmpegCommandBuilder commandBuilder;
  final MediaProbe mediaProbe;
  final FfmpegToolValidator toolValidator;

  @override
  Stream<RenderProgress> render(ShortsRenderJob job) {
    final cancellation = _FfmpegRenderCancellation();
    final controller = StreamController<RenderProgress>(
      onCancel: cancellation.cancel,
    );
    _run(job, controller, cancellation);
    return controller.stream;
  }

  Future<void> _run(
    ShortsRenderJob job,
    StreamController<RenderProgress> controller,
    _FfmpegRenderCancellation cancellation,
  ) async {
    try {
      if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
        controller.add(
          const RenderProgress(
            status: RenderJobStatus.failed,
            message: 'Local FFmpeg rendering is enabled for desktop first.',
          ),
        );
        return;
      }

      final toolError = await toolValidator.validate();
      if (cancellation.isCanceled) {
        return;
      }
      if (toolError != null) {
        controller.add(
          RenderProgress(status: RenderJobStatus.failed, message: toolError),
        );
        return;
      }

      if (!File(job.source.path).existsSync()) {
        controller.add(
          RenderProgress(
            status: RenderJobStatus.failed,
            message: 'Source video was not found: ${job.source.path}',
          ),
        );
        return;
      }

      final audioOverlayPath = job.audioOverlayPath;
      if (audioOverlayPath != null &&
          audioOverlayPath.trim().isNotEmpty &&
          !File(audioOverlayPath).existsSync()) {
        controller.add(
          RenderProgress(
            status: RenderJobStatus.failed,
            message: 'Uploaded audio was not found: $audioOverlayPath',
          ),
        );
        return;
      }

      final outputDirectory = p.dirname(job.outputPath);
      if (outputDirectory.isNotEmpty) {
        Directory(outputDirectory).createSync(recursive: true);
      }

      final metadata = await _probe(job.source.path);
      if (cancellation.isCanceled) {
        return;
      }
      if (metadata == null) {
        controller.add(
          RenderProgress(
            status: RenderJobStatus.failed,
            message: 'Could not read media metadata for ${job.source.path}.',
          ),
        );
        return;
      }

      final duration = _trimmedDuration(_durationFromMetadata(metadata), job);
      final args = commandBuilder.build(job);

      controller.add(
        const RenderProgress(
          status: RenderJobStatus.running,
          fraction: 0,
          message: 'Starting FFmpeg render.',
        ),
      );

      final process = await Process.start(FfmpegExecutables.ffmpeg, args);
      cancellation.attach(process);
      if (cancellation.isCanceled) {
        process.kill();
        await process.exitCode;
        await _deletePartialOutput(job.outputPath);
        return;
      }
      final stderr = StringBuffer();
      final stdoutDone = Completer<void>();
      final stderrDone = Completer<void>();

      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              final progress = _parseProgressLine(line, duration);
              if (progress != null && !controller.isClosed) {
                controller.add(progress);
              }
            },
            onError: (_) {
              if (!stdoutDone.isCompleted) {
                stdoutDone.complete();
              }
            },
            onDone: () {
              if (!stdoutDone.isCompleted) {
                stdoutDone.complete();
              }
            },
          );

      process.stderr
          .transform(utf8.decoder)
          .listen(
            stderr.write,
            onError: (_) {
              if (!stderrDone.isCompleted) {
                stderrDone.complete();
              }
            },
            onDone: () {
              if (!stderrDone.isCompleted) {
                stderrDone.complete();
              }
            },
          );

      final exitCode = await process.exitCode;
      await Future.wait([stdoutDone.future, stderrDone.future]);

      if (cancellation.isCanceled) {
        await _deletePartialOutput(job.outputPath);
        return;
      }

      if (exitCode == 0) {
        controller.add(
          RenderProgress(
            status: RenderJobStatus.completed,
            fraction: 1,
            message: 'Render complete.',
            outputPath: job.outputPath,
          ),
        );
      } else {
        controller.add(
          RenderProgress(
            status: RenderJobStatus.failed,
            message: _failureMessage(stderr.toString()),
          ),
        );
      }
    } catch (error) {
      controller.add(
        RenderProgress(status: RenderJobStatus.failed, message: '$error'),
      );
    } finally {
      await controller.close();
    }
  }

  Future<MediaMetadata?> _probe(String inputPath) async {
    try {
      return await mediaProbe.probe(inputPath);
    } catch (_) {
      return null;
    }
  }

  Duration? _durationFromMetadata(MediaMetadata metadata) {
    final seconds = metadata.durationSeconds;
    if (seconds == null || seconds <= 0) {
      return null;
    }

    return Duration(milliseconds: (seconds * 1000).round());
  }

  Duration? _trimmedDuration(Duration? sourceDuration, ShortsRenderJob job) {
    final trimDurationSeconds = job.trimDurationSeconds;
    if (trimDurationSeconds != null) {
      return Duration(milliseconds: (trimDurationSeconds * 1000).round());
    }

    if (sourceDuration == null || job.trimStartSeconds <= 0) {
      return sourceDuration;
    }

    final trimmed =
        sourceDuration -
        Duration(milliseconds: (job.trimStartSeconds * 1000).round());
    return trimmed.isNegative ? null : trimmed;
  }

  RenderProgress? _parseProgressLine(String line, Duration? duration) {
    if (!line.startsWith('out_time_ms=')) {
      return null;
    }

    final micros = int.tryParse(line.substring('out_time_ms='.length));
    if (micros == null) {
      return null;
    }

    final fraction = duration == null || duration.inMicroseconds == 0
        ? null
        : (micros / duration.inMicroseconds).clamp(0.0, 0.99);

    return RenderProgress(
      status: RenderJobStatus.running,
      fraction: fraction,
      message: 'Rendering video.',
    );
  }

  String _failureMessage(String stderr) {
    final lines = stderr
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      return 'FFmpeg exited without details.';
    }

    if (lines.length > 8) {
      return lines.sublist(lines.length - 8).join('\n');
    }

    return lines.join('\n');
  }

  Future<void> _deletePartialOutput(String outputPath) async {
    try {
      final output = File(outputPath);
      if (await output.exists()) {
        await output.delete();
      }
    } catch (_) {
      // Cancellation still succeeds if the OS briefly retains the file lock.
    }
  }
}

class _FfmpegRenderCancellation {
  Process? _process;
  bool isCanceled = false;

  void attach(Process process) {
    _process = process;
  }

  void cancel() {
    isCanceled = true;
    _process?.kill();
  }
}
