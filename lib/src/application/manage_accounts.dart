import '../domain/publishing/auth/connected_account.dart';
import '../domain/publishing/auth/oauth_authenticator.dart';
import '../domain/publishing/auth/oauth_token_store.dart';
import '../domain/publishing/publish_target.dart';

/// Connect / disconnect / list connected platform accounts, independent of a
/// publish run.
class ManageAccounts {
  const ManageAccounts({
    required this.authenticators,
    required this.tokenStore,
  });

  final Map<PublishTarget, OAuthAuthenticator> authenticators;
  final OAuthTokenStore tokenStore;

  /// Runs the interactive OAuth flow for [target] and persists the tokens.
  /// Throws [OAuthException] on failure.
  Future<ConnectedAccount> connect(PublishTarget target) async {
    final authenticator = authenticators[target];
    if (authenticator == null) {
      throw OAuthException('${target.label} does not support sign-in.');
    }
    final credentials = await authenticator.authorize();
    await tokenStore.write(target, credentials);
    return ConnectedAccount.fromCredentials(target, credentials);
  }

  Future<void> disconnect(PublishTarget target) {
    return tokenStore.delete(target);
  }

  Future<bool> isConnected(PublishTarget target) async {
    if (!authenticators.containsKey(target)) {
      return false;
    }
    return (await tokenStore.read(target)) != null;
  }

  Future<ConnectedAccount?> connectedAccount(PublishTarget target) async {
    final credentials = await tokenStore.read(target);
    if (credentials == null) {
      return null;
    }
    return ConnectedAccount.fromCredentials(target, credentials);
  }
}
