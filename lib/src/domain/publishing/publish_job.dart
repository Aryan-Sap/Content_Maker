import 'publish_metadata.dart';
import 'publish_target.dart';

enum PublishJobStatus {
  queued,
  authorizing,
  uploading,
  processing,
  completed,
  failed,
}

/// A single request to publish one rendered video to one destination.
class PublishJob {
  const PublishJob({
    required this.videoPath,
    required this.target,
    required this.metadata,
  });

  final String videoPath;
  final PublishTarget target;
  final PublishMetadata metadata;

  /// Returns a human-readable error, or null when the job is valid.
  String? validate() {
    if (videoPath.trim().isEmpty) {
      return 'No rendered video to publish.';
    }
    return metadata.validate();
  }
}

/// Streamed progress for a publish job. Mirrors `RenderProgress` so the UI can
/// reuse the same terminal/fraction handling it already uses for rendering.
class PublishProgress {
  const PublishProgress({
    required this.target,
    required this.status,
    required this.message,
    this.fraction,
    this.remoteUrl,
    this.postId,
  });

  final PublishTarget target;
  final PublishJobStatus status;
  final String message;

  /// Upload progress in the range 0..1, when known.
  final double? fraction;

  /// Canonical URL of the published post, when the platform returns one.
  final String? remoteUrl;

  /// Platform-native identifier of the created post/video.
  final String? postId;

  bool get isTerminal =>
      status == PublishJobStatus.completed ||
      status == PublishJobStatus.failed;

  bool get isSuccess => status == PublishJobStatus.completed;

  PublishProgress copyWith({
    PublishJobStatus? status,
    String? message,
    double? fraction,
    String? remoteUrl,
    String? postId,
  }) {
    return PublishProgress(
      target: target,
      status: status ?? this.status,
      message: message ?? this.message,
      fraction: fraction ?? this.fraction,
      remoteUrl: remoteUrl ?? this.remoteUrl,
      postId: postId ?? this.postId,
    );
  }
}
