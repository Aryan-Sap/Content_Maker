import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../domain/publishing/auth/oauth_authenticator.dart';
import '../../../domain/publishing/auth/oauth_credentials.dart';
import '../../../domain/publishing/publish_target.dart';
import '../oauth/authorization_code_flow.dart';
import '../oauth/oauth_config.dart';

/// Google OAuth 2.0 for the YouTube Data API (installed-app flow + PKCE).
class YoutubeOAuthAuthenticator implements OAuthAuthenticator {
  YoutubeOAuthAuthenticator({
    http.Client? client,
    this.flow = const AuthorizationCodeFlow(),
    this.config = OAuthConfig.youtube,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final AuthorizationCodeFlow flow;
  final OAuthClientConfig config;

  @override
  PublishTarget get target => PublishTarget.youtubeShort;

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
            'client_id': config.clientId,
            'redirect_uri': redirectUri,
            'response_type': 'code',
            'scope': config.scopes.join(' '),
            'code_challenge': codeChallenge,
            'code_challenge_method': 'S256',
            'access_type': 'offline',
            'prompt': 'consent',
            'state': state,
          },
        );
      },
    );

    final response = await _client.post(
      Uri.parse(config.tokenEndpoint),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': config.clientId,
        'client_secret': config.clientSecret,
        'code': result.code,
        'code_verifier': result.codeVerifier,
        'grant_type': 'authorization_code',
        'redirect_uri': result.redirectUri,
      },
    );

    final credentials = _parseTokenResponse(response, previous: null);
    return credentials.copyWith(
      accountName: await _fetchChannelTitle(credentials.accessToken),
    );
  }

  @override
  Future<OAuthCredentials> refresh(OAuthCredentials credentials) async {
    _ensureConfigured();
    final refreshToken = credentials.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const OAuthException('YouTube session expired. Reconnect required.');
    }

    final response = await _client.post(
      Uri.parse(config.tokenEndpoint),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': config.clientId,
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
      throw OAuthException('Google token request failed: ${response.body}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final accessToken = json['access_token'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw const OAuthException('Google returned no access token.');
    }
    final expiresIn = (json['expires_in'] as num?)?.toInt();
    final scope = json['scope'] as String?;
    return OAuthCredentials(
      accessToken: accessToken,
      // Google omits the refresh token on refresh responses; keep the old one.
      refreshToken: (json['refresh_token'] as String?) ?? previous?.refreshToken,
      expiresAt: expiresIn == null
          ? null
          : DateTime.now().add(Duration(seconds: expiresIn)),
      scopes: scope?.split(' ') ?? previous?.scopes ?? const [],
      accountName: previous?.accountName,
    );
  }

  Future<String?> _fetchChannelTitle(String accessToken) async {
    try {
      final response = await _client.get(
        Uri.parse(
          'https://www.googleapis.com/youtube/v3/channels'
          '?part=snippet&mine=true',
        ),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      if (response.statusCode != 200) {
        return null;
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final items = json['items'] as List?;
      if (items == null || items.isEmpty) {
        return null;
      }
      final snippet = (items.first as Map)['snippet'] as Map?;
      return snippet?['title'] as String?;
    } catch (_) {
      return null;
    }
  }

  void _ensureConfigured() {
    if (!config.isConfigured) {
      throw const OAuthException(
        'YouTube is not configured. Provide YOUTUBE_CLIENT_ID and '
        'YOUTUBE_CLIENT_SECRET via --dart-define-from-file.',
      );
    }
  }
}
