import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:content_maker/src/application/project_store.dart';
import 'package:content_maker/src/domain/editing/manual_edit_project.dart';
import 'package:content_maker/src/domain/editing/timeline_clip.dart';

void main() {
  test('manual edit project json round-trips value objects', () {
    final project = ManualEditProject(
      outputPath: 'out.mp4',
      width: 1080,
      height: 1920,
      frameRate: 60,
      backgroundHexColor: '101418',
      blurredBackgroundEnabled: true,
      clips: [
        TimelineClip.fromPath(
          id: 'video-a',
          type: TimelineClipType.video,
          path: 'a.mp4',
          timelineStartSeconds: 0,
          durationSeconds: 8,
        ).copyWith(
          x: 0.2,
          saturation: 1.2,
          temperature: 0.35,
          tint: -0.2,
          highlights: 0.3,
          shadows: -0.15,
          fade: 0.1,
          vignette: 0.4,
          lutId: 'cinematic',
          lutIntensity: 0.65,
          speed: 0.5,
          reverse: true,
          animation: const ClipAnimation(type: ClipAnimationType.kenBurnsIn),
        ),
        TimelineClip.fromPath(
          id: 'audio-a',
          type: TimelineClipType.audio,
          path: 'music.mp3',
          timelineStartSeconds: 1,
          durationSeconds: 12,
        ).copyWith(audioFadeInSeconds: 0.4, audioFadeOutSeconds: 1.2),
        TimelineClip(
          id: 'text-a',
          type: TimelineClipType.text,
          path: '',
          name: 'Text overlay',
          trackIndex: 0,
          timelineStartSeconds: 2,
          trimStartSeconds: 0,
          trimEndSeconds: 5,
          volume: 1,
          enabled: true,
          muted: false,
          locked: false,
          transition: TimelineTransition.cut,
          transitionDurationSeconds: 0.35,
          hasAudio: false,
          text: const TextSpec(
            content: 'Round trip',
            font: 'Verdana',
            size: 84,
            colorHex: 'C9F63C',
            x: 120,
            y: -220,
            fadeOutSeconds: 0.8,
          ),
        ),
      ],
    );

    final restored = ManualEditProject.fromJson(project.toJson());

    expect(restored.toJson(), project.toJson());
    expect(restored.clips.first.colorGrade.lutId, 'cinematic');
    expect(restored.clips.first.motion.speed, 0.5);
    expect(restored.clips.first.animation.type, ClipAnimationType.kenBurnsIn);
    expect(restored.clips[1].audio.fadeOutSeconds, 1.2);
    expect(restored.clips.last.text?.fadeOutSeconds, 0.8);
  });

  test('project store saves and opens cmproj json', () async {
    final directory = await Directory.systemTemp.createTemp(
      'content_maker_project_store_test_',
    );
    addTearDown(() async {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });

    final path = '${directory.path}${Platform.pathSeparator}sample.cmproj';
    final project = ManualEditProject(
      outputPath: 'out.mp4',
      width: 1080,
      height: 1080,
      frameRate: 30,
      backgroundHexColor: '000000',
      blurredBackgroundEnabled: false,
      clips: [
        TimelineClip.fromPath(
          id: 'video-a',
          type: TimelineClipType.video,
          path: 'a.mp4',
          timelineStartSeconds: 0,
        ),
      ],
    );

    const store = ProjectStore();
    await store.save(project, path);

    final restored = await store.open(path);

    expect(restored.toJson(), project.toJson());
  });
}
