import 'package:flutter_test/flutter_test.dart';

import 'package:content_maker/src/domain/editing/manual_edit_project.dart';
import 'package:content_maker/src/domain/editing/manual_render_job.dart';
import 'package:content_maker/src/domain/editing/timeline_clip.dart';
import 'package:content_maker/src/infrastructure/ffmpeg/ffmpeg_manual_timeline_command_builder.dart';

void main() {
  test('builds a layered manual timeline command', () {
    final project = ManualEditProject(
      outputPath: 'timeline.mp4',
      width: 1080,
      height: 1920,
      frameRate: 60,
      backgroundHexColor: '101418',
      blurredBackgroundEnabled: false,
      clips: [
        TimelineClip.fromPath(
          id: 'video-a',
          type: TimelineClipType.video,
          path: 'a.mp4',
          timelineStartSeconds: 0,
        ).copyWith(trimEndSeconds: 6, scale: 1.2, x: 0.25),
        TimelineClip.fromPath(
          id: 'video-b',
          type: TimelineClipType.video,
          path: 'b.mp4',
          timelineStartSeconds: 2,
        ).copyWith(trimStartSeconds: 1, trimEndSeconds: 5, trackIndex: 1),
        TimelineClip.fromPath(
          id: 'audio-a',
          type: TimelineClipType.audio,
          path: 'music.mp3',
          timelineStartSeconds: 1.5,
        ).copyWith(trimEndSeconds: 10, volume: 0.6),
      ],
    );

    final args = const FfmpegManualTimelineCommandBuilder().build(
      ManualRenderJob(project: project),
    );
    final filter = args[args.indexOf('-filter_complex') + 1];

    expect(args, containsAllInOrder(['-i', 'a.mp4', '-i', 'b.mp4']));
    expect(args, containsAllInOrder(['-i', 'music.mp3']));
    expect(args, containsAllInOrder(['-map', '[v]', '-map', '[a]']));
    expect(args.last, 'timeline.mp4');

    expect(filter, contains('color=c=0x101418:s=1080x1920'));
    expect(filter, contains('[0:v]trim=start=0:duration=6'));
    expect(filter, contains('scale=iw*1.2:ih*1.2'));
    expect(filter, contains("enable='between(t,0,6)'"));
    expect(filter, contains('[1:v]trim=start=1:duration=4'));
    expect(filter, contains("enable='between(t,2,6)'"));
    expect(filter, contains('[2:a]atrim=start=0:duration=10'));
    expect(filter, contains('volume=0.6'));
    expect(filter, contains('adelay=1500:all=1'));
    expect(filter, contains('amix=inputs=1'));
  });

  test('omits audio mapping when the project has no audible audio clips', () {
    final project = ManualEditProject(
      outputPath: 'timeline.mp4',
      width: 1920,
      height: 1080,
      frameRate: 30,
      backgroundHexColor: '101418',
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

    final args = const FfmpegManualTimelineCommandBuilder().build(
      ManualRenderJob(project: project),
    );
    final filter = args[args.indexOf('-filter_complex') + 1];

    expect(args, contains('-an'));
    expect(args, isNot(contains('[a]')));
    expect(filter, contains('fps=30,format=yuv420p[v]'));
  });

  test('applies grading, motion processing, and adjacent transitions', () {
    final project = ManualEditProject(
      outputPath: 'timeline.mp4',
      width: 1920,
      height: 1080,
      frameRate: 60,
      backgroundHexColor: '080808',
      blurredBackgroundEnabled: false,
      clips: [
        TimelineClip.fromPath(
          id: 'outgoing',
          type: TimelineClipType.video,
          path: 'outgoing.mp4',
          timelineStartSeconds: 0,
          durationSeconds: 4,
        ).copyWith(trackIndex: 1),
        TimelineClip.fromPath(
          id: 'incoming',
          type: TimelineClipType.video,
          path: 'incoming.mp4',
          timelineStartSeconds: 4,
          durationSeconds: 5,
        ).copyWith(
          saturation: 1.25,
          contrast: 1.1,
          gamma: 0.95,
          sharpness: 0.4,
          motionBlur: true,
          motionInterpolation: true,
          panningBlurIntensity: 0.5,
          transition: TimelineTransition.dissolve,
          transitionDurationSeconds: 0.5,
        ),
      ],
    );

    final filter = const FfmpegManualTimelineCommandBuilder().buildFilterGraph(
      ManualRenderJob(project: project),
    );

    expect(filter, contains('tpad=stop_mode=clone:stop_duration=0.5'));
    expect(filter.indexOf('[0:v]trim'), lessThan(filter.indexOf('[1:v]trim')));
    expect(filter, contains("enable='between(t,0,4.5)'"));
    expect(filter, contains('minterpolate=fps=60'));
    expect(filter, contains("tmix=frames=3:weights='1 2 1'"));
    expect(filter, contains('avgblur=sizeX=11:sizeY=1'));
    expect(
      filter,
      contains('eq=brightness=0:saturation=1.25:contrast=1.1:gamma=0.95'),
    );
    expect(filter, contains('unsharp=5:5:0.4'));
    expect(filter, contains('fade=t=in:st=4:d=0.5:alpha=1'));
  });

  test('applies roadmap color, speed, reverse, and audio fade controls', () {
    final project = ManualEditProject(
      outputPath: 'timeline.mp4',
      width: 1920,
      height: 1080,
      frameRate: 30,
      backgroundHexColor: '080808',
      blurredBackgroundEnabled: false,
      clips: [
        TimelineClip.fromPath(
          id: 'video-a',
          type: TimelineClipType.video,
          path: 'video.mp4',
          timelineStartSeconds: 0,
          durationSeconds: 8,
        ).copyWith(
          temperature: 0.4,
          tint: -0.2,
          highlights: 0.25,
          shadows: -0.25,
          fade: 0.12,
          vignette: 0.5,
          lutId: 'cinematic',
          speed: 0.5,
          reverse: true,
        ),
        TimelineClip.fromPath(
          id: 'audio-a',
          type: TimelineClipType.audio,
          path: 'music.mp3',
          timelineStartSeconds: 0,
          durationSeconds: 8,
        ).copyWith(speed: 2, audioFadeInSeconds: 0.5, audioFadeOutSeconds: 1),
      ],
    );

    final filter = const FfmpegManualTimelineCommandBuilder().buildFilterGraph(
      ManualRenderJob(project: project),
    );

    expect(filter, contains('[0:v]trim=start=0:duration=8'));
    expect(filter, contains(',reverse'));
    expect(filter, contains('setpts=(PTS-STARTPTS)/0.5+0/TB'));
    expect(filter, contains('colortemperature=temperature=7900'));
    expect(filter, contains('colorbalance=gm=0.05'));
    expect(filter, contains('curves='));
    expect(filter, contains('vignette=angle=0.8'));
    expect(filter, contains('lut3d='));
    expect(filter, contains('cinematic.cube'));
    expect(filter, contains('[1:a]atrim=start=0:duration=8'));
    expect(filter, contains('atempo=2'));
    expect(filter, contains('afade=t=in:st=0:d=0.5'));
    expect(filter, contains('afade=t=out:st=3:d=1'));
  });

  test('covers the transition hold with real footage when available', () {
    final project = ManualEditProject(
      outputPath: 'timeline.mp4',
      width: 1920,
      height: 1080,
      frameRate: 60,
      backgroundHexColor: '080808',
      blurredBackgroundEnabled: false,
      clips: [
        TimelineClip.fromPath(
          id: 'outgoing',
          type: TimelineClipType.video,
          path: 'outgoing.mp4',
          timelineStartSeconds: 0,
          durationSeconds: 4,
        ).copyWith(sourceDurationSeconds: 10),
        TimelineClip.fromPath(
          id: 'incoming',
          type: TimelineClipType.video,
          path: 'incoming.mp4',
          timelineStartSeconds: 4,
          durationSeconds: 5,
        ).copyWith(
          transition: TimelineTransition.dissolve,
          transitionDurationSeconds: 0.5,
          x: 0.1,
        ),
      ],
    );

    final filter = const FfmpegManualTimelineCommandBuilder().buildFilterGraph(
      ManualRenderJob(project: project),
    );

    // Outgoing source has spare footage past the cut, so the 0.5s hold is
    // real frames (trim extended) instead of a frozen tpad frame.
    expect(filter, contains('[0:v]trim=start=0:duration=4.5'));
    expect(filter, isNot(contains('tpad=')));
    expect(filter, contains("enable='between(t,0,4.5)'"));
  });

  test('fade-through-black fades the outgoing clip out and the incoming in', () {
    final project = ManualEditProject(
      outputPath: 'timeline.mp4',
      width: 1920,
      height: 1080,
      frameRate: 60,
      backgroundHexColor: '080808',
      blurredBackgroundEnabled: false,
      clips: [
        TimelineClip.fromPath(
          id: 'outgoing',
          type: TimelineClipType.video,
          path: 'outgoing.mp4',
          timelineStartSeconds: 0,
          durationSeconds: 4,
        ).copyWith(x: 0.1),
        TimelineClip.fromPath(
          id: 'incoming',
          type: TimelineClipType.video,
          path: 'incoming.mp4',
          timelineStartSeconds: 4,
          durationSeconds: 5,
        ).copyWith(
          transition: TimelineTransition.fadeThroughBlack,
          transitionDurationSeconds: 1,
          x: 0.1,
        ),
      ],
    );

    final filter = const FfmpegManualTimelineCommandBuilder().buildFilterGraph(
      ManualRenderJob(project: project),
    );

    expect(filter, contains('fade=t=out:st=3.5:d=0.5'));
    expect(filter, contains('fade=t=in:st=4:d=0.5'));
    // No overlap for fade-through-black: the outgoing clip ends at the cut.
    expect(filter, isNot(contains('tpad=')));
    expect(filter, contains("enable='between(t,0,4)'"));
  });

  test('zoom transitions animate scale and dissolve in', () {
    final project = ManualEditProject(
      outputPath: 'timeline.mp4',
      width: 1920,
      height: 1080,
      frameRate: 60,
      backgroundHexColor: '080808',
      blurredBackgroundEnabled: false,
      clips: [
        TimelineClip.fromPath(
          id: 'outgoing',
          type: TimelineClipType.video,
          path: 'outgoing.mp4',
          timelineStartSeconds: 0,
          durationSeconds: 4,
        ).copyWith(x: 0.1),
        TimelineClip.fromPath(
          id: 'incoming',
          type: TimelineClipType.video,
          path: 'incoming.mp4',
          timelineStartSeconds: 4,
          durationSeconds: 5,
        ).copyWith(
          transition: TimelineTransition.zoomIn,
          transitionDurationSeconds: 0.5,
          x: 0.1,
        ),
      ],
    );

    final filter = const FfmpegManualTimelineCommandBuilder().buildFilterGraph(
      ManualRenderJob(project: project),
    );

    expect(filter, contains('fade=t=in:st=4:d=0.5:alpha=1'));
    expect(filter, contains('eval=frame'));
    expect(filter, contains('scale=w=iw*(1+0.25*max(0\\,1-(t-4)/0.5))'));
    // Zoom overlaps the previous clip, which is held for the duration.
    expect(filter, contains('tpad=stop_mode=clone:stop_duration=0.5'));
  });

  test('circle transitions iris with an animated vignette', () {
    final project = ManualEditProject(
      outputPath: 'timeline.mp4',
      width: 1920,
      height: 1080,
      frameRate: 60,
      backgroundHexColor: '080808',
      blurredBackgroundEnabled: false,
      clips: [
        TimelineClip.fromPath(
          id: 'outgoing',
          type: TimelineClipType.video,
          path: 'outgoing.mp4',
          timelineStartSeconds: 0,
          durationSeconds: 4,
        ).copyWith(x: 0.1),
        TimelineClip.fromPath(
          id: 'incoming',
          type: TimelineClipType.video,
          path: 'incoming.mp4',
          timelineStartSeconds: 4,
          durationSeconds: 5,
        ).copyWith(
          transition: TimelineTransition.circleOpen,
          transitionDurationSeconds: 0.5,
          x: 0.1,
        ),
      ],
    );

    final filter = const FfmpegManualTimelineCommandBuilder().buildFilterGraph(
      ManualRenderJob(project: project),
    );

    expect(
      filter,
      contains("vignette=angle='(PI/2)*max(0\\,1-(t-4)/0.5)':eval=frame"),
    );
  });

  test('eases slide transition movement in the export graph', () {
    final project = ManualEditProject(
      outputPath: 'timeline.mp4',
      width: 1920,
      height: 1080,
      frameRate: 60,
      backgroundHexColor: '080808',
      blurredBackgroundEnabled: true,
      clips: [
        TimelineClip.fromPath(
          id: 'outgoing',
          type: TimelineClipType.video,
          path: 'outgoing.mp4',
          timelineStartSeconds: 0,
          durationSeconds: 4,
        ),
        TimelineClip.fromPath(
          id: 'incoming',
          type: TimelineClipType.video,
          path: 'incoming.mp4',
          timelineStartSeconds: 4,
          durationSeconds: 4,
        ).copyWith(
          transition: TimelineTransition.slideLeft,
          transitionDurationSeconds: 0.5,
        ),
      ],
    );

    final filter = const FfmpegManualTimelineCommandBuilder().buildFilterGraph(
      ManualRenderJob(project: project),
    );

    expect(filter, contains('max(0\\,min(1\\,(t-4)/0.5))'));
    expect(filter, contains('(1-(max(0\\,min(1\\,(t-4)/0.5)))'));
  });

  test('keeps adjacent precision cuts frame-tight without transition hold', () {
    final project = ManualEditProject(
      outputPath: 'timeline.mp4',
      width: 1920,
      height: 1080,
      frameRate: 60,
      backgroundHexColor: '080808',
      blurredBackgroundEnabled: true,
      clips: [
        TimelineClip.fromPath(
          id: 'first',
          type: TimelineClipType.video,
          path: 'first.mp4',
          timelineStartSeconds: 0,
          durationSeconds: 4,
        ),
        TimelineClip.fromPath(
          id: 'second',
          type: TimelineClipType.video,
          path: 'second.mp4',
          timelineStartSeconds: 4,
          durationSeconds: 5,
        ),
      ],
    );

    final filter = const FfmpegManualTimelineCommandBuilder().buildFilterGraph(
      ManualRenderJob(project: project),
    );

    expect(filter, isNot(contains('tpad=')));
    expect(filter, contains("enable='between(t,0,4)'"));
    expect(filter, contains("enable='between(t,4,9)'"));
  });

  test('uses normalized concat for simple adjacent full-frame clips', () {
    final project = ManualEditProject(
      outputPath: 'timeline.mp4',
      width: 1080,
      height: 1920,
      frameRate: 60,
      backgroundHexColor: '080808',
      blurredBackgroundEnabled: false,
      clips: [
        TimelineClip.fromPath(
          id: 'first',
          type: TimelineClipType.video,
          path: 'first.mp4',
          timelineStartSeconds: 0,
          durationSeconds: 4,
        ).copyWith(sourceDurationSeconds: 4, hasAudio: true),
        TimelineClip.fromPath(
          id: 'second',
          type: TimelineClipType.video,
          path: 'second.mp4',
          timelineStartSeconds: 4,
          durationSeconds: 5,
        ).copyWith(sourceDurationSeconds: 5, hasAudio: true),
      ],
    );

    final args = const FfmpegManualTimelineCommandBuilder().build(
      ManualRenderJob(project: project),
    );
    final filter = args[args.indexOf('-filter_complex') + 1];

    expect(filter, contains('scale=1080:1920'));
    expect(filter, contains('pad=1080:1920'));
    expect(filter, contains('setsar=1'));
    expect(filter, contains('fps=60'));
    expect(filter, contains('format=yuv420p'));
    expect(filter, contains('[v0][a0][v1][a1]concat=n=2:v=1:a=1[outv][outa]'));
    expect(args, containsAllInOrder(['-map', '[outv]', '-map', '[outa]']));
  });
}
