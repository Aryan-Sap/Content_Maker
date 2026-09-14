import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../domain/publishing/auth/oauth_authenticator.dart';
import '../../../domain/publishing/auth/oauth_credentials.dart';
import '../../../domain/publishing/publish_target.dart';
import '../oauth/authorization_code_flow.dart';
import '../oauth/oauth_config.dart';

/// Instagram Login for professional (Business or Creator) accounts.
///
/// Meta requires the redirect URI to match the URI registered in the app
/// dashboard, so Instagram uses a stable local port instead of the ephemeral
/// port used by Google and TikTok.
class InstagramOAuthAuthenticator implements OAuthAuthenticator {
  InstagramOAuthAuthenticator({
    http.Client? client,
    this.flow = const AuthorizationCodeFlow(),
    this.config = OAuthConfig.instagram,
  }) : _client = client ?? http.Client();

  static const loopbackPort = 8752;
  static const redirectUri = 'http://127.0.0.1:$loopbackPort/';

  final http.Client _client;
  final AuthorizationCodeFlow flow;
  final OAuthClientConfig config;

  @override
  PublishTarget get target => PublishTarget.instagramReel;

  @override
  Future<OAuthCredentials> authorize() async {
    _ensureConfigured();

    final result = await flow.obtainCode(
      loopbackPort: loopbackPort,
      buildAuthorizationUrl:
          ({required redirectUri, required codeChallenge, required state}) {
            return Uri.parse(config.authorizationEndpoint).replace(
              queryParameters: {
                'client_id': config.clientId,
                'redirect_uri': redirectUri,
                'response_type': 'code',
                'scope': config.scopes.join(','),
                'state': state,
                'force_reauth': 'true',
              },
            );
          },
    );

    final shortLivedResponse = await _client.post(
      Uri.parse(config.tokenEndpoint),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': config.clientId,
        'client_secret': config.clientSecret,
        'grant_type': 'authorization_code',
        'redirect_uri': result.redirectUri,
        'code': result.code,
      },
    );
    final shortLived = _decodeTokenResponse(
      shortLivedResponse,
      providerAction: 'sign-in',
    );

    final shortToken = shortLived['access_token'] as String?;
    if (shortToken == null || shortToken.isEmpty) {
      throw const OAuthException('Instagram returned no access token.');
    }

    final longLivedResponse = await _client.get(
      Uri.parse('https://graph.instagram.com/access_token').replace(
        queryParameters: {
          'grant_type': 'ig_exchange_token',
          'client_secret': config.clientSecret,
          'access_token': shortToken,
        },
      ),
    );
    final longLived = _decodeTokenResponse(
      longLivedResponse,
      providerAction: 'token exchange',
    );
    final accessToken = longLived['access_token'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw const OAuthException(
        'Instagram returned no long-lived access token.',
      );
    }

    final expiresIn = (longLived['expires_in'] as num?)?.toInt();
    return OAuthCredentials(
      accessToken: accessToken,
      // Instagram refreshes its long-lived access token directly.
      refreshToken: accessToken,
      expiresAt: expiresIn == null
          ? null
          : DateTime.now().add(Duration(seconds: expiresIn)),
      scopes: config.scopes,
      accountName: await _fetchUsername(accessToken),
    );
  }

  @override
  Future<OAuthCredentials> refresh(OAuthCredentials credentials) async {
    _ensureConfigured();
    final currentToken = credentials.refreshToken ?? credentials.accessToken;
    if (currentToken.isEmpty) {
      throw const OAuthException(
        'Instagram session expired. Reconnect required.',
      );
    }

    final response = await _client.get(
      Uri.parse('https://graph.instagram.com/refresh_access_token').replace(
        queryParameters: {
          'grant_type': 'ig_refresh_token',
          'access_token': currentToken,
        },
      ),
    );
    final json = _decodeTokenResponse(
      response,
      providerAction: 'token refresh',
    );
    final accessToken = json['access_token'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw const OAuthException('Instagram returned no refreshed token.');
    }
    final expiresIn = (json['expires_in'] as num?)?.toInt();

    return OAuthCredentials(
      accessToken: accessToken,
      refreshToken: accessToken,
      expiresAt: expiresIn == null
          ? credentials.expiresAt
          : DateTime.now().add(Duration(seconds: expiresIn)),
      scopes: credentials.scopes.isEmpty ? config.scopes : credentials.scopes,
      accountName: credentials.accountName,
    );
  }

  Map<String, dynamic> _decodeTokenResponse(
    http.Response response, {
    required String providerAction,
  }) {
    Map<String, dynamic>? json;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        json = decoded;
      }
    } on FormatException {
      // The status handling below reports a useful provider error.
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = json?['error'];
      final message = error is Map
          ? error['message']
          : json?['error_message'] ?? json?['message'];
      throw OAuthException(
        'Instagram $providerAction failed: ${message ?? response.body}',
      );
    }
    if (json == null) {
      throw OAuthException(
        'Instagram $providerAction returned an invalid response.',
      );
    }
    return json;
  }

  Future<String?> _fetchUsername(String accessToken) async {
    try {
      final response = await _client.get(
        Uri.parse('https://graph.instagram.com/me').replace(
          queryParameters: {
            'fields': 'id,user_id,username,name',
            'access_token': accessToken,
          },
        ),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final username = json['username'] as String?;
      return username == null || username.isEmpty ? null : '@$username';
    } catch (_) {
      return null;
    }
  }

  void _ensureConfigured() {
    if (!config.isConfigured) {
      throw const OAuthException(
        'Instagram is not configured. Add INSTAGRAM_APP_ID and '
        'INSTAGRAM_APP_SECRET, then register $redirectUri in the Meta app.',
      );
    }
  }
}
