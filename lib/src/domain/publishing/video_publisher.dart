import 'auth/oauth_credentials.dart';
import 'publish_job.dart';
import 'publish_target.dart';

/// Uploads a rendered video to one destination. Mirrors the `VideoProcessor`
/// contract used by the renderer so the UI can stream progress the same way.
abstract interface class VideoPublisher {
  PublishTarget get target;

  /// Publishes [job] using already-valid [credentials]. Callers are expected
  /// to refresh/authorize before invoking so this method can assume a usable
  /// access token.
  Stream<PublishProgress> publish(PublishJob job, OAuthCredentials credentials);
}
