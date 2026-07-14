import '../publish_target.dart';
import 'oauth_credentials.dart';

/// Thrown when a platform authorization flow fails or is cancelled.
class OAuthException implements Exception {
  const OAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Runs the interactive login and silent refresh for one platform.
abstract interface class OAuthAuthenticator {
  PublishTarget get target;

  /// Opens the system browser for consent and returns fresh credentials.
  /// Throws [OAuthException] on failure or cancellation.
  Future<OAuthCredentials> authorize();

  /// Exchanges a refresh token for a new access token. Throws
  /// [OAuthException] when the credentials cannot be refreshed.
  Future<OAuthCredentials> refresh(OAuthCredentials credentials);
}
