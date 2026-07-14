import '../domain/rendering/render_job.dart';
import '../domain/rendering/video_processor.dart';

class CreateShortsExport {
  const CreateShortsExport(this._videoProcessor);

  final VideoProcessor _videoProcessor;

  Stream<RenderProgress> call(ShortsRenderJob job) {
    final validationError = job.validate();
    if (validationError != null) {
      return Stream.value(
        RenderProgress(
          status: RenderJobStatus.failed,
          message: validationError,
        ),
      );
    }

    return _videoProcessor.render(job);
  }
}
