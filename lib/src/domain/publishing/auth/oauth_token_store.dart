import '../publish_target.dart';
import 'oauth_credentials.dart';

/// Persists OAuth credentials per platform. Implemented over secure OS storage.
abstract interface class OAuthTokenStore {
  Future<OAuthCredentials?> read(PublishTarget target);

  Future<void> write(PublishTarget target, OAuthCredentials credentials);

  Future<void> delete(PublishTarget target);
}
