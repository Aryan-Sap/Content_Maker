import 'package:flutter_test/flutter_test.dart';

import 'package:content_maker/src/domain/rendering/export_settings.dart';
import 'package:content_maker/src/domain/rendering/render_job.dart';
import 'package:content_maker/src/domain/rendering/render_preset.dart';
import 'package:content_maker/src/domain/rendering/video_asset.dart';
import 'package:content_maker/src/infrastructure/ffmpeg/ffmpeg_command_builder.dart';

void main() {
  test('builds the Shorts-style FFmpeg command', () {
    const job = ShortsRenderJob(
      source: VideoAsset('input.mp4'),
      outputPath: 'output.mp4',
      preset: RenderPreset.gameplayShort,
    );

    final args = const FfmpegCommandBuilder().build(job);
    final filter = args[args.indexOf('-filter_complex') + 1];

    expect(args, containsAllInOrder(['-i', 'input.mp4']));
    expect(args, containsAllInOrder(['-map', '[v]']));
    expect(args, containsAllInOrder(['-map', '0:a?']));
    expect(args, containsAllInOrder(['-c:v', 'libx264']));
    expect(args, containsAllInOrder(['-crf', '16']));
    expect(args.last, 'output.mp4');

    expect(filter, contains('scale=1080:1920'));
    expect(filter, contains('flags=lanczos'));
    expect(filter, contains('gblur=sigma=34:steps=3'));
    expect(filter, contains('crop=1080:608'));
    expect(filter, contains('fps=60'));
    expect(filter, contains('setsar=1,format=yuv420p[v]'));
  });

  test('uses minterpolate when motion interpolation is enabled', () {
    final preset = RenderPreset.gameplayShort.copyWith(
      exportSettings: RenderPreset.gameplayShort.exportSettings.copyWith(
        temporalSmoothing: TemporalSmoothingMode.motionInterpolation,
      ),
    );
    final job = ShortsRenderJob(
      source: const VideoAsset('input.mp4'),
      outputPath: 'output.mp4',
      preset: preset,
    );

    final filter = const FfmpegCommandBuilder().buildFilterGraph(job);

    expect(filter, contains('minterpolate=fps=60'));
    expect(filter, isNot(contains('fps=60,format')));
    // The expensive interpolation runs on the cropped foreground band only;
    // the blurred background gets a cheap fps conversion instead.
    expect(
      filter.indexOf('minterpolate='),
      greaterThan(filter.indexOf('crop=1080:608')),
    );
    expect(
      filter.indexOf('minterpolate='),
      lessThan(filter.indexOf('[fg]')),
    );
    expect(filter.substring(0, filter.indexOf('[bg]')), contains('fps=60,'));
  });

  test('honours the configured interpolation quality', () {
    final fastPreset = RenderPreset.gameplayShort.copyWith(
      exportSettings: RenderPreset.gameplayShort.exportSettings.copyWith(
        temporalSmoothing: TemporalSmoothingMode.motionInterpolation,
        interpolationQuality: InterpolationQuality.fast,
      ),
    );
    final qualityPreset = RenderPreset.gameplayShort.copyWith(
      exportSettings: RenderPreset.gameplayShort.exportSettings.copyWith(
        temporalSmoothing: TemporalSmoothingMode.motionInterpolation,
        interpolationQuality: InterpolationQuality.quality,
      ),
    );

    final fastFilter = const FfmpegCommandBuilder().buildFilterGraph(
      ShortsRenderJob(
        source: const VideoAsset('input.mp4'),
        outputPath: 'output.mp4',
        preset: fastPreset,
      ),
    );
    final qualityFilter = const FfmpegCommandBuilder().buildFilterGraph(
      ShortsRenderJob(
        source: const VideoAsset('input.mp4'),
        outputPath: 'output.mp4',
        preset: qualityPreset,
      ),
    );

    expect(fastFilter, contains('me=hexbs'));
    expect(fastFilter, contains('search_param=16'));
    expect(qualityFilter, contains('mc_mode=aobmc'));
    expect(qualityFilter, contains('vsbmc=1'));
  });

  test('adds trim arguments when a render range is set', () {
    const job = ShortsRenderJob(
      source: VideoAsset('input.mp4'),
      outputPath: 'output.mp4',
      preset: RenderPreset.gameplayShort,
      trimStartSeconds: 2.5,
      trimEndSeconds: 8,
    );

    final args = const FfmpegCommandBuilder().build(job);

    expect(args, containsAllInOrder(['-ss', '2.5', '-i', 'input.mp4']));
    expect(args, containsAllInOrder(['-t', '5.5', '-filter_complex']));
  });

  test('adds temporal blur to the background when motion blur is enabled', () {
    final preset = RenderPreset.gameplayShort.copyWith(
      exportSettings: RenderPreset.gameplayShort.exportSettings.copyWith(
        motionBlur: true,
      ),
    );
    final job = ShortsRenderJob(
      source: const VideoAsset('input.mp4'),
      outputPath: 'output.mp4',
      preset: preset,
    );

    final filter = const FfmpegCommandBuilder().buildFilterGraph(job);

    expect(filter, contains("tmix=frames=3:weights='1 2 1'"));
    expect(
      filter.indexOf("tmix=frames=3:weights='1 2 1'"),
      lessThan(filter.indexOf('[bg]')),
    );
  });

  test('adds panning blur to the background when intensity is set', () {
    final preset = RenderPreset.gameplayShort.copyWith(
      exportSettings: RenderPreset.gameplayShort.exportSettings.copyWith(
        panningBlurIntensity: 0.5,
      ),
    );
    final job = ShortsRenderJob(
      source: const VideoAsset('input.mp4'),
      outputPath: 'output.mp4',
      preset: preset,
    );

    final filter = const FfmpegCommandBuilder().buildFilterGraph(job);

    expect(filter, contains('avgblur=sizeX=11:sizeY=1'));
    expect(
      filter.indexOf('avgblur=sizeX=11:sizeY=1'),
      lessThan(filter.indexOf('[bg]')),
    );
  });

  test('mixes uploaded audio with independent volumes', () {
    const job = ShortsRenderJob(
      source: VideoAsset('input.mp4'),
      outputPath: 'output.mp4',
      preset: RenderPreset.gameplayShort,
      audioOverlayPath: 'music.mp3',
      sourceAudioVolume: 0.45,
      overlayAudioVolume: 1.2,
    );

    final args = const FfmpegCommandBuilder().build(job);
    final filter = args[args.indexOf('-filter_complex') + 1];

    expect(args, containsAllInOrder(['-i', 'input.mp4', '-i', 'music.mp3']));
    expect(args, containsAllInOrder(['-map', '[v]', '-map', '[a]']));
    expect(filter, contains('[0:a]volume=0.45[srca]'));
    expect(filter, contains('[1:a]volume=1.2[overa]'));
    expect(filter, contains('amix=inputs=2'));
    expect(filter, contains('normalize=0[a]'));
  });

  test('applies original audio volume without uploaded audio', () {
    const job = ShortsRenderJob(
      source: VideoAsset('input.mp4'),
      outputPath: 'output.mp4',
      preset: RenderPreset.gameplayShort,
      sourceAudioVolume: 0.5,
    );

    final args = const FfmpegCommandBuilder().build(job);

    expect(args, containsAllInOrder(['-map', '0:a?']));
    expect(args, containsAllInOrder(['-filter:a', 'volume=0.5']));
  });

  test('uses the selected composition resolution', () {
    final preset = RenderPreset.gameplayShort.copyWith(
      composition: RenderPreset.gameplayShort.composition.copyWith(
        width: 1920,
        height: 1080,
        foregroundHeight: 810,
      ),
    );
    final job = ShortsRenderJob(
      source: const VideoAsset('input.mp4'),
      outputPath: 'output.mp4',
      preset: preset,
    );

    final filter = const FfmpegCommandBuilder().buildFilterGraph(job);

    expect(filter, contains('scale=1920:1080'));
    expect(filter, contains('crop=1920:810'));
  });
}
