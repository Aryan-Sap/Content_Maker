import '../publish_target.dart';
import 'oauth_credentials.dart';

/// UI-facing snapshot of a connected platform account.
class ConnectedAccount {
  const ConnectedAccount({
    required this.target,
    this.displayName,
    this.expiresAt,
  });

  final PublishTarget target;
  final String? displayName;
  final DateTime? expiresAt;

  String get label => displayName ?? target.label;

  factory ConnectedAccount.fromCredentials(
    PublishTarget target,
    OAuthCredentials credentials,
  ) {
    return ConnectedAccount(
      target: target,
      displayName: credentials.accountName,
      expiresAt: credentials.expiresAt,
    );
  }
}
