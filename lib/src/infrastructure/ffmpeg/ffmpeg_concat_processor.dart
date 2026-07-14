import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/rendering/concat_merge_job.dart';
import '../../domain/rendering/render_job.dart';
import 'ffmpeg_concat_command_builder.dart';
import 'ffmpeg_executables.dart';
import 'ffmpeg_tool_validator.dart';

class FfmpegConcatProcessor implements ConcatMergeProcessor {
  const FfmpegConcatProcessor({
    this.commandBuilder = const FfmpegConcatCommandBuilder(),
    this.toolValidator = const FfmpegToolValidator(),
  });

  final FfmpegConcatCommandBuilder commandBuilder;
  final FfmpegToolValidator toolValidator;

  @override
  Stream<RenderProgress> render(ConcatMergeJob job) {
    final controller = StreamController<RenderProgress>();
    _run(job, controller);
    return controller.stream;
  }

  Future<void> _run(
    ConcatMergeJob job,
    StreamController<RenderProgress> controller,
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
      if (toolError != null) {
        controller.add(
          RenderProgress(status: RenderJobStatus.failed, message: toolError),
        );
        return;
      }

      final validationError = job.validate();
      if (validationError != null) {
        controller.add(
          RenderProgress(
            status: RenderJobStatus.failed,
            message: validationError,
          ),
        );
        return;
      }

      for (final input in job.inputs) {
        if (!File(input.path).existsSync()) {
          controller.add(
            RenderProgress(
              status: RenderJobStatus.failed,
              message: 'Source video was not found: ${input.path}',
            ),
          );
          return;
        }
      }

      final outputDirectory = p.dirname(job.outputPath);
      if (outputDirectory.isNotEmpty) {
        Directory(outputDirectory).createSync(recursive: true);
      }

      final args = commandBuilder.build(job);
      controller.add(
        const RenderProgress(
          status: RenderJobStatus.running,
          fraction: 0,
          message: 'Starting merge export.',
        ),
      );

      final process = await Process.start(FfmpegExecutables.ffmpeg, args);
      final stderr = StringBuffer();
      final stdoutDone = Completer<void>();
      final stderrDone = Completer<void>();
      final duration = Duration(
        milliseconds: (job.durationSeconds * 1000).round(),
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

      if (exitCode == 0) {
        controller.add(
          RenderProgress(
            status: RenderJobStatus.completed,
            fraction: 1,
            message: 'Merge export complete.',
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
      message: 'Merging videos.',
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
}
