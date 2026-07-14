import '../domain/editing/manual_render_job.dart';
import '../domain/rendering/render_job.dart';

class CreateManualTimelineExport {
  const CreateManualTimelineExport(this._timelineProcessor);

  final ManualTimelineProcessor _timelineProcessor;

  Stream<RenderProgress> call(ManualRenderJob job) {
    final validationError = job.validate();
    if (validationError != null) {
      return Stream.value(
        RenderProgress(
          status: RenderJobStatus.failed,
          message: validationError,
        ),
      );
    }

    return _timelineProcessor.render(job);
  }
}
