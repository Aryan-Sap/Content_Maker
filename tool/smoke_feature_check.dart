import 'dart:io';

import 'package:content_maker/src/application/auto_edit_preset_store.dart';
import 'package:content_maker/src/application/create_manual_timeline_export.dart';
import 'package:content_maker/src/application/create_shorts_export.dart';
import 'package:content_maker/src/domain/editing/manual_edit_project.dart';
import 'package:content_maker/src/domain/editing/manual_render_job.dart';
import 'package:content_maker/src/domain/editing/timeline_clip.dart';
import 'package:content_maker/src/domain/rendering/auto_edit_preset.dart';
import 'package:content_maker/src/domain/rendering/render_job.dart';
import 'package:content_maker/src/domain/rendering/render_preset.dart';
import 'package:content_maker/src/domain/rendering/video_asset.dart';
import 'package:content_maker/src/infrastructure/ffmpeg/ffmpeg_executables.dart';
import 'package:content_maker/src/infrastructure/ffmpeg/ffmpeg_manual_timeline_processor.dart';
import 'package:content_maker/src/infrastructure/ffmpeg/ffmpeg_video_processor.dart';
import 'package:path/path.dart' as p;

Future<void> main() async {
  final root = Directory.current.path;
  final mediaDir = p.join(root, 'build', 'manual_smoke');
  final outputDir = p.join(mediaDir, 'outputs');
  Directory(outputDir).createSync(recursive: true);

  final sourceA = p.join(mediaDir, 'source_color_steps.mp4');
  final sourceB = p.join(mediaDir, 'source_testsrc.mp4');
  final overlay = p.join(mediaDir, 'overlay_tone.wav');
  for (final path in [sourceA, sourceB, overlay]) {
    if (!File(path).existsSync()) {
      throw StateError('Missing smoke media: $path');
    }
  }

  final manualExport = CreateManualTimelineExport(
    const FfmpegManualTimelineProcessor(),
  );
  final simpleExport = CreateShortsExport(const FfmpegVideoProcessor());

  final results = <String>[];

  await _runPresetSmoke(outputDir);
  results.add('preset save/load');

  final simplePreset = RenderPreset.gameplayShort.copyWith(
    composition: RenderPreset.gameplayShort.composition.copyWith(
      width: 360,
      height: 640,
      foregroundHeight: 240,
      blurSigma: 8,
      blurSteps: 1,
      sharpness: 0.2,
    ),
    exportSettings: RenderPreset.gameplayShort.exportSettings.copyWith(
      frameRate: 24,
      crf: 28,
      encoderPreset: 'veryfast',
      motionBlur: true,
      panningBlurIntensity: 0.2,
    ),
  );

  for (final entry in [
    MapEntry(sourceA, p.join(outputDir, 'simple_queue_a.mp4')),
    MapEntry(sourceB, p.join(outputDir, 'simple_queue_b.mp4')),
  ]) {
    await _renderSimple(
      simpleExport,
      ShortsRenderJob(
        source: VideoAsset(entry.key),
        outputPath: entry.value,
        preset: simplePreset,
        trimStartSeconds: 0,
        trimEndSeconds: 2,
        audioOverlayPath: overlay,
        sourceAudioVolume: 0.5,
        overlayAudioVolume: 0.4,
      ),
    );
    await _expectDuration(entry.value, 1.7, 2.4);
  }
  results.add('simple batch queue with audio overlay');

  final speedOutput = p.join(outputDir, 'manual_speed_2x.mp4');
  await _renderManual(
    manualExport,
    _manualProject(
      outputPath: speedOutput,
      clips: [
        TimelineClip.fromPath(
          id: 'speed',
          type: TimelineClipType.video,
          path: sourceA,
          timelineStartSeconds: 0,
          durationSeconds: 4,
          sourceDurationSeconds: 4,
          hasAudio: true,
        ).copyWith(speed: 2),
      ],
    ),
  );
  await _expectDuration(speedOutput, 1.8, 2.35);
  results.add('manual speed changes playback duration');

  final reverseOutput = p.join(outputDir, 'manual_reverse.mp4');
  await _renderManual(
    manualExport,
    _manualProject(
      outputPath: reverseOutput,
      clips: [
        TimelineClip.fromPath(
          id: 'reverse',
          type: TimelineClipType.video,
          path: sourceA,
          timelineStartSeconds: 0,
          durationSeconds: 4,
          sourceDurationSeconds: 4,
          hasAudio: true,
        ).copyWith(reverse: true),
      ],
    ),
  );
  final firstReversePixel = await _firstPixel(reverseOutput);
  _expect(
    firstReversePixel.r > 180 &&
        firstReversePixel.g > 180 &&
        firstReversePixel.b < 100,
    'Reverse smoke expected the first rendered frame to come from the yellow end of the source, got $firstReversePixel.',
  );
  results.add('manual reverse outputs reversed frames');

  final filterOutput = p.join(outputDir, 'manual_lut_filter.mp4');
  await _renderManual(
    manualExport,
    _manualProject(
      outputPath: filterOutput,
      clips: [
        TimelineClip.fromPath(
          id: 'filter',
          type: TimelineClipType.video,
          path: sourceB,
          timelineStartSeconds: 0,
          durationSeconds: 2,
          sourceDurationSeconds: 5,
          hasAudio: true,
        ).copyWith(
          brightness: 0.08,
          contrast: 1.3,
          saturation: 0.55,
          gamma: 1.05,
          temperature: 0.2,
          tint: -0.1,
          lutId: 'cinematic',
          lutIntensity: 0.65,
          sharpness: 0.25,
        ),
      ],
    ),
  );
  await _expectDuration(filterOutput, 1.8, 2.4);
  results.add('manual color grade and LUT filter export');

  final transitionOutput = p.join(outputDir, 'manual_transition_slide.mp4');
  await _renderManual(
    manualExport,
    _manualProject(
      outputPath: transitionOutput,
      clips: [
        TimelineClip.fromPath(
          id: 'outgoing',
          type: TimelineClipType.video,
          path: sourceA,
          timelineStartSeconds: 0,
          durationSeconds: 2,
          sourceDurationSeconds: 4,
          hasAudio: false,
        ).copyWith(trimEndSeconds: 2),
        TimelineClip.fromPath(
          id: 'incoming',
          type: TimelineClipType.video,
          path: sourceB,
          timelineStartSeconds: 2,
          durationSeconds: 2,
          sourceDurationSeconds: 5,
          hasAudio: false,
        ).copyWith(
          trimEndSeconds: 2,
          transition: TimelineTransition.slideLeft,
          transitionDurationSeconds: 0.5,
        ),
      ],
    ),
  );
  await _expectDuration(transitionOutput, 3.7, 4.4);
  results.add('manual draggable transition render path');

  stdout.writeln('Smoke checks passed:');
  for (final result in results) {
    stdout.writeln('- $result');
  }
}

ManualEditProject _manualProject({
  required String outputPath,
  required List<TimelineClip> clips,
}) {
  return ManualEditProject(
    outputPath: outputPath,
    width: 360,
    height: 640,
    frameRate: 24,
    backgroundHexColor: '101418',
    blurredBackgroundEnabled: true,
    clips: clips,
  );
}

Future<void> _runPresetSmoke(String outputDir) async {
  final path = p.join(outputDir, 'auto_edit_presets_smoke.json');
  final store = AutoEditPresetStore(storePath: path);
  final preset = AutoEditPreset(
    id: 'smoke',
    name: 'Smoke Preset',
    renderPreset: RenderPreset.gameplayShort.copyWith(
      exportSettings: RenderPreset.gameplayShort.exportSettings.copyWith(
        frameRate: 24,
      ),
    ),
    trimStartSeconds: 0.25,
    trimEndSeconds: 2.25,
    sourceAudioVolume: 0.4,
    overlayAudioVolume: 0.8,
  );
  await store.saveAll([preset]);
  final restored = await store.load();
  _expect(restored.length == 1, 'Expected one restored preset.');
  _expect(restored.single.name == preset.name, 'Preset name did not persist.');
  _expect(
    restored.single.overlayAudioVolume == preset.overlayAudioVolume,
    'Preset audio edit values did not persist.',
  );
}

Future<void> _renderSimple(
  CreateShortsExport exporter,
  ShortsRenderJob job,
) async {
  await _consumeRenderStream('simple ${p.basename(job.outputPath)}', () {
    return exporter(job);
  });
}

Future<void> _renderManual(
  CreateManualTimelineExport exporter,
  ManualEditProject project,
) async {
  await _consumeRenderStream('manual ${p.basename(project.outputPath)}', () {
    return exporter(ManualRenderJob(project: project));
  });
}

Future<void> _consumeRenderStream(
  String label,
  Stream<RenderProgress> Function() start,
) async {
  RenderProgress? last;
  await for (final progress in start()) {
    last = progress;
  }
  _expect(last != null, '$label did not emit render progress.');
  _expect(
    last!.status == RenderJobStatus.completed,
    '$label failed: ${last.message}',
  );
  final output = last.outputPath;
  _expect(
    output != null && File(output).existsSync(),
    '$label did not write output.',
  );
}

Future<void> _expectDuration(String path, double min, double max) async {
  final result = await Process.run(FfmpegExecutables.ffprobe, [
    '-v',
    'error',
    '-show_entries',
    'format=duration',
    '-of',
    'default=nokey=1:noprint_wrappers=1',
    path,
  ]);
  _expect(result.exitCode == 0, 'ffprobe failed for $path: ${result.stderr}');
  final duration = double.tryParse('${result.stdout}'.trim());
  _expect(duration != null, 'Could not parse duration for $path.');
  _expect(
    duration! >= min && duration <= max,
    '${p.basename(path)} duration ${duration.toStringAsFixed(2)}s was outside ${min}s-${max}s.',
  );
}

Future<_Rgb> _firstPixel(String path) async {
  final result = await Process.run(FfmpegExecutables.ffmpeg, [
    '-v',
    'error',
    '-i',
    path,
    '-frames:v',
    '1',
    '-vf',
    'scale=1:1:flags=area,format=rgb24',
    '-f',
    'rawvideo',
    'pipe:1',
  ], stdoutEncoding: null);
  _expect(result.exitCode == 0, 'Could not read first pixel: ${result.stderr}');
  final bytes = result.stdout as List<int>;
  _expect(bytes.length >= 3, 'First pixel extraction returned no RGB bytes.');
  return _Rgb(bytes[0], bytes[1], bytes[2]);
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}

class _Rgb {
  const _Rgb(this.r, this.g, this.b);

  final int r;
  final int g;
  final int b;

  @override
  String toString() => 'rgb($r, $g, $b)';
}
