import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/editing/manual_render_job.dart';
import '../../domain/rendering/render_job.dart';
import 'ffmpeg_manual_timeline_command_builder.dart';
import 'ffmpeg_executables.dart';
import 'ffmpeg_tool_validator.dart';

class FfmpegManualTimelineProcessor implements ManualTimelineProcessor {
  const FfmpegManualTimelineProcessor({
    this.commandBuilder = const FfmpegManualTimelineCommandBuilder(),
    this.toolValidator = const FfmpegToolValidator(),
  });

  final FfmpegManualTimelineCommandBuilder commandBuilder;
  final FfmpegToolValidator toolValidator;

  @override
  Stream<RenderProgress> render(ManualRenderJob job) {
    final cancellation = _FfmpegRenderCancellation();
    final controller = StreamController<RenderProgress>(
      onCancel: cancellation.cancel,
    );
    _run(job, controller, cancellation);
    return controller.stream;
  }

  Future<void> _run(
    ManualRenderJob job,
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

      for (final clip in job.project.clips.where((clip) => clip.enabled)) {
        if (!File(clip.path).existsSync()) {
          controller.add(
            RenderProgress(
              status: RenderJobStatus.failed,
              message: 'Media was not found: ${clip.path}',
            ),
          );
          return;
        }
      }

      final outputDirectory = p.dirname(job.project.outputPath);
      if (outputDirectory.isNotEmpty) {
        Directory(outputDirectory).createSync(recursive: true);
      }

      final args = commandBuilder.build(job);
      controller.add(
        const RenderProgress(
          status: RenderJobStatus.running,
          fraction: 0,
          message: 'Starting timeline export.',
        ),
      );

      final process = await Process.start(FfmpegExecutables.ffmpeg, args);
      cancellation.attach(process);
      if (cancellation.isCanceled) {
        process.kill();
        await process.exitCode;
        await _deletePartialOutput(job.project.outputPath);
        return;
      }
      final stderr = StringBuffer();
      final stdoutDone = Completer<void>();
      final stderrDone = Completer<void>();
      final duration = Duration(
        milliseconds: (job.project.durationSeconds * 1000).round(),
      );

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
        await _deletePartialOutput(job.project.outputPath);
        return;
      }

      if (exitCode == 0) {
        controller.add(
          RenderProgress(
            status: RenderJobStatus.completed,
            fraction: 1,
            message: 'Timeline export complete.',
            outputPath: job.project.outputPath,
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

  RenderProgress? _parseProgressLine(String line, Duration duration) {
    if (!line.startsWith('out_time_ms=')) {
      return null;
    }

    final micros = int.tryParse(line.substring('out_time_ms='.length));
    if (micros == null || duration.inMicroseconds == 0) {
      return null;
    }

    final fraction = (micros / duration.inMicroseconds).clamp(0.0, 0.99);
    return RenderProgress(
      status: RenderJobStatus.running,
      fraction: fraction,
      message: 'Exporting timeline.',
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
