import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../domain/publishing/auth/oauth_authenticator.dart';
import '../../../domain/publishing/auth/oauth_credentials.dart';
import '../../../domain/publishing/publish_target.dart';
import '../oauth/authorization_code_flow.dart';
import '../oauth/oauth_config.dart';

/// TikTok OAuth v2 (authorization code + PKCE). Note TikTok names its client
/// identifier `client_key` rather than `client_id`.
class TiktokOAuthAuthenticator implements OAuthAuthenticator {
  TiktokOAuthAuthenticator({
    http.Client? client,
    this.flow = const AuthorizationCodeFlow(),
    this.config = OAuthConfig.tiktok,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final AuthorizationCodeFlow flow;
  final OAuthClientConfig config;

  @override
  PublishTarget get target => PublishTarget.tiktok;

  @override
  Future<OAuthCredentials> authorize() async {
    _ensureConfigured();

    final result = await flow.obtainCode(
      buildAuthorizationUrl: ({
        required redirectUri,
        required codeChallenge,
        required state,
      }) {
        return Uri.parse(config.authorizationEndpoint).replace(
          queryParameters: {
            'client_key': config.clientId,
            'redirect_uri': redirectUri,
            'response_type': 'code',
            'scope': config.scopes.join(','),
            'code_challenge': codeChallenge,
            'code_challenge_method': 'S256',
            'state': state,
          },
        );
      },
    );

    final response = await _client.post(
      Uri.parse(config.tokenEndpoint),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_key': config.clientId,
        'client_secret': config.clientSecret,
        'code': result.code,
        'code_verifier': result.codeVerifier,
        'grant_type': 'authorization_code',
        'redirect_uri': result.redirectUri,
      },
    );

    return _parseTokenResponse(response, previous: null);
  }

  @override
  Future<OAuthCredentials> refresh(OAuthCredentials credentials) async {
    _ensureConfigured();
    final refreshToken = credentials.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const OAuthException('TikTok session expired. Reconnect required.');
    }

    final response = await _client.post(
      Uri.parse(config.tokenEndpoint),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_key': config.clientId,
        'client_secret': config.clientSecret,
        'refresh_token': refreshToken,
        'grant_type': 'refresh_token',
      },
    );

    return _parseTokenResponse(response, previous: credentials);
  }

  OAuthCredentials _parseTokenResponse(
    http.Response response, {
    required OAuthCredentials? previous,
  }) {
    if (response.statusCode != 200) {
      throw OAuthException('TikTok token request failed: ${response.body}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    // TikTok returns errors with a 200 status and an `error` field.
    final error = json['error'];
    if (error != null && error != '' && error != 'ok') {
      throw OAuthException(
        'TikTok authorization failed: ${json['error_description'] ?? error}',
      );
    }
    final accessToken = json['access_token'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw const OAuthException('TikTok returned no access token.');
    }
    final expiresIn = (json['expires_in'] as num?)?.toInt();
    final scope = json['scope'] as String?;
    return OAuthCredentials(
      accessToken: accessToken,
      refreshToken: (json['refresh_token'] as String?) ?? previous?.refreshToken,
      expiresAt: expiresIn == null
          ? null
          : DateTime.now().add(Duration(seconds: expiresIn)),
      scopes: scope?.split(',') ?? previous?.scopes ?? const [],
      accountName: previous?.accountName ?? 'TikTok account',
    );
  }

  void _ensureConfigured() {
    if (!config.isConfigured) {
      throw const OAuthException(
        'TikTok is not configured. Provide TIKTOK_CLIENT_KEY and '
        'TIKTOK_CLIENT_SECRET via --dart-define-from-file.',
      );
    }
  }
}
