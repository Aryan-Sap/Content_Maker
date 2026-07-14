import 'render_job.dart';
import 'render_preset.dart';

class ConcatMergeInput {
  const ConcatMergeInput({
    required this.path,
    required this.durationSeconds,
    this.hasAudio = true,
    this.trimStartSeconds = 0,
    this.trimEndSeconds,
  });

  final String path;
  final double durationSeconds;
  final bool hasAudio;
  final double trimStartSeconds;
  final double? trimEndSeconds;

  double get trimDurationSeconds {
    final trimEnd = trimEndSeconds ?? durationSeconds;
    return trimEnd - trimStartSeconds;
  }

  String? validate() {
    if (path.trim().isEmpty) {
      return 'Every merge input needs a source path.';
    }
    if (durationSeconds <= 0) {
      return '$path needs a positive duration.';
    }
    if (trimStartSeconds < 0) {
      return '$path trim start cannot be negative.';
    }
    final trimEnd = trimEndSeconds;
    if (trimEnd != null && trimEnd <= trimStartSeconds) {
      return '$path trim end must be greater than trim start.';
    }
    if (trimEnd != null && trimEnd > durationSeconds) {
      return '$path trim end cannot exceed the source duration.';
    }
    if (trimDurationSeconds <= 0) {
      return '$path needs a positive trimmed duration.';
    }
    return null;
  }
}

class ConcatMergeJob {
  const ConcatMergeJob({
    required this.inputs,
    required this.outputPath,
    required this.preset,
  });

  final List<ConcatMergeInput> inputs;
  final String outputPath;
  final RenderPreset preset;

  double get durationSeconds {
    var total = 0.0;
    for (final input in inputs) {
      total += input.trimDurationSeconds;
    }
    return total;
  }

  String? validate() {
    if (inputs.length < 2) {
      return 'Choose at least two videos to merge.';
    }
    if (outputPath.trim().isEmpty) {
      return 'Choose an output path.';
    }
    for (final input in inputs) {
      final validationError = input.validate();
      if (validationError != null) {
        return validationError;
      }
    }
    return null;
  }
}

abstract interface class ConcatMergeProcessor {
  Stream<RenderProgress> render(ConcatMergeJob job);
}
