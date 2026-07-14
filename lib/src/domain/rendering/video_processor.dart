import 'render_job.dart';

abstract interface class VideoProcessor {
  Stream<RenderProgress> render(ShortsRenderJob job);
}
