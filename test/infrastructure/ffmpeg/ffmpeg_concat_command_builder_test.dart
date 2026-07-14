import 'package:flutter_test/flutter_test.dart';

import 'package:content_maker/src/domain/rendering/concat_merge_job.dart';
import 'package:content_maker/src/domain/rendering/render_preset.dart';
import 'package:content_maker/src/infrastructure/ffmpeg/ffmpeg_concat_command_builder.dart';

void main() {
  test('builds normalized concat graph for two inputs with audio', () {
    final job = ConcatMergeJob(
      inputs: const [
        ConcatMergeInput(path: 'a.mp4', durationSeconds: 4, hasAudio: true),
        ConcatMergeInput(path: 'b.mp4', durationSeconds: 5, hasAudio: true),
      ],
      outputPath: 'merged.mp4',
      preset: RenderPreset.gameplayShort,
    );

    final args = const FfmpegConcatCommandBuilder().build(job);
    final filter = args[args.indexOf('-filter_complex') + 1];

    expect(args, containsAllInOrder(['-i', 'a.mp4', '-i', 'b.mp4']));
    expect(filter, contains('setsar=1'));
    expect(filter, contains('fps=60'));
    expect(filter, contains('format=yuv420p'));
    expect(filter, contains('setpts=PTS-STARTPTS[v0]'));
    expect(filter, contains('setpts=PTS-STARTPTS[v1]'));
    expect(filter, contains('aresample=async=1:first_pts=0'));
    expect(filter, contains('[v0][a0][v1][a1]concat=n=2:v=1:a=1[outv][outa]'));
  });

  test('injects silent audio for inputs without audio', () {
    final job = ConcatMergeJob(
      inputs: const [
        ConcatMergeInput(
          path: 'silent.mp4',
          durationSeconds: 7.25,
          hasAudio: false,
        ),
        ConcatMergeInput(path: 'voice.mp4', durationSeconds: 3, hasAudio: true),
      ],
      outputPath: 'merged.mp4',
      preset: RenderPreset.gameplayShort,
    );

    final args = const FfmpegConcatCommandBuilder().build(job);
    final filter = args[args.indexOf('-filter_complex') + 1];

    expect(
      args,
      containsAllInOrder([
        '-i',
        'silent.mp4',
        '-f',
        'lavfi',
        '-t',
        '7.25',
        '-i',
        'anullsrc=channel_layout=stereo:sample_rate=48000',
        '-i',
        'voice.mp4',
      ]),
    );
    expect(filter, contains('[1:a]aresample=async=1:first_pts=0'));
    expect(filter, contains('concat=n=2:v=1:a=1[outv][outa]'));
  });

  test('uses input count for N-way concat', () {
    final job = ConcatMergeJob(
      inputs: const [
        ConcatMergeInput(path: 'a.mp4', durationSeconds: 1),
        ConcatMergeInput(path: 'b.mp4', durationSeconds: 1),
        ConcatMergeInput(path: 'c.mp4', durationSeconds: 1),
      ],
      outputPath: 'merged.mp4',
      preset: RenderPreset.gameplayShort,
    );

    final filter = const FfmpegConcatCommandBuilder().buildFilterGraph(job);

    expect(filter, contains('concat=n=3:v=1:a=1[outv][outa]'));
    expect(filter, contains('[v0][a0][v1][a1][v2][a2]'));
  });

  test('uses preset values for normalization and encode args', () {
    final preset = RenderPreset.gameplayShort.copyWith(
      composition: RenderPreset.gameplayShort.composition.copyWith(
        width: 1920,
        height: 1080,
      ),
      exportSettings: RenderPreset.gameplayShort.exportSettings.copyWith(
        frameRate: 30,
      ),
    );
    final job = ConcatMergeJob(
      inputs: const [
        ConcatMergeInput(path: 'a.mp4', durationSeconds: 1),
        ConcatMergeInput(path: 'b.mp4', durationSeconds: 1),
      ],
      outputPath: 'merged.mp4',
      preset: preset,
    );

    final args = const FfmpegConcatCommandBuilder().build(job);
    final filter = args[args.indexOf('-filter_complex') + 1];

    expect(filter, contains('scale=1920:1080'));
    expect(filter, contains('pad=1920:1080'));
    expect(filter, contains('fps=30'));
    expect(args, containsAllInOrder(['-c:v', 'libx264']));
    expect(args, containsAllInOrder(['-crf', '16']));
    expect(args, containsAllInOrder(['-preset', 'medium']));
    expect(args, containsAllInOrder(['-c:a', 'aac']));
    expect(args, containsAllInOrder(['-b:a', '192k']));
    expect(args, containsAllInOrder(['-movflags', '+faststart']));
    expect(args.last, 'merged.mp4');
  });
}
