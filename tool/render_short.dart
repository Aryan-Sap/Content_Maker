import 'dart:io';

import 'package:content_maker/src/application/create_concat_merge_export.dart';
import 'package:content_maker/src/domain/rendering/export_settings.dart';
import 'package:content_maker/src/domain/rendering/render_job.dart';
import 'package:content_maker/src/domain/rendering/render_preset.dart';
import 'package:content_maker/src/domain/rendering/video_asset.dart';
import 'package:content_maker/src/infrastructure/ffmpeg/ffmpeg_concat_processor.dart';
import 'package:content_maker/src/infrastructure/ffmpeg/ffmpeg_media_probe.dart';
import 'package:content_maker/src/infrastructure/ffmpeg/ffmpeg_video_processor.dart';

Future<void> main(List<String> arguments) async {
  final args = List<String>.of(arguments);
  final interpolate = args.remove('--interpolate');

  if (args.length < 2) {
    stderr.writeln(
      'Usage: dart run tool/render_short.dart <input.mp4> [input2.mp4 ...] <output.mp4> [--interpolate]',
    );
    exitCode = 64;
    return;
  }

  final preset = RenderPreset.gameplayShort.copyWith(
    exportSettings: RenderPreset.gameplayShort.exportSettings.copyWith(
      temporalSmoothing: interpolate
          ? TemporalSmoothingMode.motionInterpolation
          : TemporalSmoothingMode.fpsConversion,
    ),
  );

  final outputPath = args.removeLast();
  final progressStream = args.length == 1
      ? const FfmpegVideoProcessor().render(
          ShortsRenderJob(
            source: VideoAsset(args.single),
            outputPath: outputPath,
            preset: preset,
          ),
        )
      : const CreateConcatMergeExport(
          FfmpegConcatProcessor(),
          FfmpegMediaProbe(),
        )(inputPaths: args, outputPath: outputPath, preset: preset);

  await for (final progress in progressStream) {
    final percent = progress.fraction == null
        ? ''
        : ' ${(progress.fraction! * 100).toStringAsFixed(0)}%';
    stdout.writeln('${progress.status.name}: ${progress.message}$percent');

    if (progress.status == RenderJobStatus.failed) {
      exitCode = 1;
    }
  }
}
