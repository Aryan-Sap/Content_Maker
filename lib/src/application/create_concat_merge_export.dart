import 'dart:io';

import '../domain/rendering/concat_merge_job.dart';
import '../domain/rendering/media_metadata.dart';
import '../domain/rendering/render_job.dart';
import '../domain/rendering/render_preset.dart';

class CreateConcatMergeExport {
  const CreateConcatMergeExport(this._processor, this._mediaProbe);

  final ConcatMergeProcessor _processor;
  final MediaProbe _mediaProbe;

  Stream<RenderProgress> call({
    required List<String> inputPaths,
    required String outputPath,
    required RenderPreset preset,
  }) async* {
    final paths = inputPaths
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .toList();
    if (paths.length < 2) {
      yield const RenderProgress(
        status: RenderJobStatus.failed,
        message: 'Choose at least two videos to merge.',
      );
      return;
    }
    if (outputPath.trim().isEmpty) {
      yield const RenderProgress(
        status: RenderJobStatus.failed,
        message: 'Choose an output path.',
      );
      return;
    }

    final inputs = <ConcatMergeInput>[];
    for (final path in paths) {
      if (!File(path).existsSync()) {
        yield RenderProgress(
          status: RenderJobStatus.failed,
          message: 'Source video was not found: $path',
        );
        return;
      }

      final metadata = await _probe(path);
      if (metadata == null) {
        yield RenderProgress(
          status: RenderJobStatus.failed,
          message: 'Could not read media metadata for $path.',
        );
        return;
      }

      final durationSeconds = metadata.durationSeconds;
      if (durationSeconds == null || durationSeconds <= 0) {
        yield RenderProgress(
          status: RenderJobStatus.failed,
          message: 'Could not read a valid duration for $path.',
        );
        return;
      }

      inputs.add(
        ConcatMergeInput(
          path: path,
          durationSeconds: durationSeconds,
          hasAudio: metadata.hasAudio,
        ),
      );
    }

    final job = ConcatMergeJob(
      inputs: inputs,
      outputPath: outputPath.trim(),
      preset: preset,
    );
    final validationError = job.validate();
    if (validationError != null) {
      yield RenderProgress(
        status: RenderJobStatus.failed,
        message: validationError,
      );
      return;
    }

    yield* _processor.render(job);
  }

  Future<MediaMetadata?> _probe(String path) async {
    try {
      return await _mediaProbe.probe(path);
    } catch (_) {
      return null;
    }
  }
}
