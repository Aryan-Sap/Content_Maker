import 'package:url_launcher/url_launcher.dart';

import '../../../domain/publishing/auth/oauth_authenticator.dart';
import 'loopback_redirect_server.dart';
import 'pkce.dart';

/// The authorization code plus the exact values used to obtain it, needed for
/// the subsequent token exchange.
class AuthorizationCodeResult {
  const AuthorizationCodeResult({
    required this.code,
    required this.redirectUri,
    required this.codeVerifier,
  });

  final String code;
  final String redirectUri;
  final String codeVerifier;
}

/// Drives the installed-app authorization-code + PKCE handshake: starts a
/// loopback server, opens the system browser to the consent screen, and waits
/// for the redirect. The caller performs the platform-specific token exchange.
class AuthorizationCodeFlow {
  const AuthorizationCodeFlow();

  /// [buildAuthorizationUrl] receives the redirect URI, PKCE challenge, and
  /// state, and must return the full provider authorization URL.
  Future<AuthorizationCodeResult> obtainCode({
    required Uri Function({
      required String redirectUri,
      required String codeChallenge,
      required String state,
    })
    buildAuthorizationUrl,
    Duration timeout = const Duration(minutes: 15),
  }) async {
    final pkce = PkcePair.generate();
    final state = generateOAuthState();
    final server = await LoopbackRedirectServer.start();
    final redirectUri = server.redirectUri;

    try {
      final authUrl = buildAuthorizationUrl(
        redirectUri: redirectUri,
        codeChallenge: pkce.challenge,
        state: state,
      );

      if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
        throw const OAuthException(
          'Could not open the browser for authorization.',
        );
      }

      final redirect = await server.waitForCode(
        expectedState: state,
        timeout: timeout,
      );

      return AuthorizationCodeResult(
        code: redirect.code,
        redirectUri: redirectUri,
        codeVerifier: pkce.verifier,
      );
    } finally {
      await server.close();
    }
  }
}
