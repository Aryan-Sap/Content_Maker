import 'render_preset.dart';
import 'video_asset.dart';

enum RenderJobStatus { queued, running, completed, failed, canceled }

class ShortsRenderJob {
  const ShortsRenderJob({
    required this.source,
    required this.outputPath,
    required this.preset,
    this.trimStartSeconds = 0,
    this.trimEndSeconds,
    this.audioOverlayPath,
    this.sourceAudioVolume = 1,
    this.overlayAudioVolume = 0.75,
  });

  final VideoAsset source;
  final String outputPath;
  final RenderPreset preset;
  final double trimStartSeconds;
  final double? trimEndSeconds;
  final String? audioOverlayPath;
  final double sourceAudioVolume;
  final double overlayAudioVolume;

  double? get trimDurationSeconds {
    final trimEnd = trimEndSeconds;
    if (trimEnd == null) {
      return null;
    }
    return trimEnd - trimStartSeconds;
  }

  String? validate() {
    if (source.isEmpty) {
      return 'Choose a source video path.';
    }
    if (outputPath.trim().isEmpty) {
      return 'Choose an output path.';
    }
    if (trimStartSeconds < 0) {
      return 'Trim start cannot be negative.';
    }
    final trimEnd = trimEndSeconds;
    if (trimEnd != null && trimEnd <= trimStartSeconds) {
      return 'Trim end must be greater than trim start.';
    }
    if (sourceAudioVolume < 0 || sourceAudioVolume > 2) {
      return 'Original audio volume must be between 0% and 200%.';
    }
    if (overlayAudioVolume < 0 || overlayAudioVolume > 2) {
      return 'Uploaded audio volume must be between 0% and 200%.';
    }
    return null;
  }
}

class RenderProgress {
  const RenderProgress({
    required this.status,
    required this.message,
    this.fraction,
    this.outputPath,
  });

  final RenderJobStatus status;
  final String message;
  final double? fraction;
  final String? outputPath;

  bool get isTerminal =>
      status == RenderJobStatus.completed ||
      status == RenderJobStatus.failed ||
      status == RenderJobStatus.canceled;
}
