import '../rendering/render_job.dart';
import 'manual_edit_project.dart';

class ManualRenderJob {
  const ManualRenderJob({required this.project});

  final ManualEditProject project;

  String? validate() {
    if (project.outputPath.trim().isEmpty) {
      return 'Choose an output path.';
    }
    if (project.width <= 0 || project.height <= 0) {
      return 'Canvas size must be greater than zero.';
    }
    if (project.frameRate <= 0) {
      return 'Frame rate must be greater than zero.';
    }
    if (project.enabledVideoClips.isEmpty) {
      return 'Add at least one visible video clip.';
    }

    for (final clip in project.clips) {
      if (!clip.isText && clip.path.trim().isEmpty) {
        return 'Every clip needs a source path.';
      }
      if (clip.timelineStartSeconds < 0) {
        return '${clip.name} starts before the timeline.';
      }
      if (clip.trimStartSeconds < 0) {
        return '${clip.name} has a negative trim start.';
      }
      if (clip.trimEndSeconds <= clip.trimStartSeconds) {
        return '${clip.name} trim end must be greater than trim start.';
      }
      final sourceDurationSeconds = clip.sourceDurationSeconds;
      if (sourceDurationSeconds != null &&
          clip.trimEndSeconds > sourceDurationSeconds) {
        return '${clip.name} trim end cannot exceed the source duration.';
      }
      if (clip.scale <= 0) {
        return '${clip.name} scale must be greater than zero.';
      }
      if (clip.opacity < 0 || clip.opacity > 1) {
        return '${clip.name} opacity must be between 0% and 100%.';
      }
      if (clip.volume < 0 || clip.volume > 2) {
        return '${clip.name} volume must be between 0% and 200%.';
      }
      if (clip.speed < 0.1 || clip.speed > 100) {
        return '${clip.name} speed must be between 0.1x and 100x.';
      }
      if (clip.audioFadeInSeconds < 0 || clip.audioFadeOutSeconds < 0) {
        return '${clip.name} audio fades cannot be negative.';
      }
      final text = clip.text;
      if (clip.isText && text != null) {
        if (text.size <= 0) {
          return '${clip.name} font size must be greater than zero.';
        }
        if (text.fadeOutSeconds < 0 ||
            text.fadeOutSeconds > clip.durationSeconds) {
          return '${clip.name} fade-out must fit within its visible duration.';
        }
      }
    }
    return null;
  }
}

abstract interface class ManualTimelineProcessor {
  Stream<RenderProgress> render(ManualRenderJob job);
}
