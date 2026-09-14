import 'dart:convert';
import 'dart:io';

import '../../../domain/publishing/publish_target.dart';

/// OAuth client configuration for one platform.
class OAuthClientConfig {
  const OAuthClientConfig({
    required this.clientId,
    required this.clientSecret,
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    required this.scopes,
  });

  final String clientId;

  /// Installed-app "secret". For desktop clients this is not truly secret, but
  /// Google still requires it in the token exchange. TikTok calls it a secret.
  final String clientSecret;

  final String authorizationEndpoint;
  final String tokenEndpoint;
  final List<String> scopes;

  bool get isConfigured =>
      _hasConfiguredValue(clientId) && _hasConfiguredValue(clientSecret);

  static bool _hasConfiguredValue(String value) {
    final trimmed = value.trim();
    return trimmed.isNotEmpty && !trimmed.startsWith('REPLACE_WITH');
  }
}

/// Reads OAuth credentials from compile-time defines so secrets never live in
/// source control. Provide them at run/build time, for example:
///
/// ```
/// flutter run -d windows --dart-define-from-file=oauth.local.json
/// ```
///
/// where `oauth.local.json` (git-ignored) contains:
///
/// ```json
/// {
///   "YOUTUBE_CLIENT_ID": "...apps.googleusercontent.com",
///   "YOUTUBE_CLIENT_SECRET": "...",
///   "TIKTOK_CLIENT_KEY": "...",
///   "TIKTOK_CLIENT_SECRET": "...",
///   "INSTAGRAM_APP_ID": "...",
///   "INSTAGRAM_APP_SECRET": "..."
/// }
/// ```
class OAuthConfig {
  const OAuthConfig._();

  static const String localConfigPath = 'oauth.local.json';

  static const String _youtubeClientId = String.fromEnvironment(
    'YOUTUBE_CLIENT_ID',
  );
  static const String _youtubeClientSecret = String.fromEnvironment(
    'YOUTUBE_CLIENT_SECRET',
  );
  static const String _tiktokClientKey = String.fromEnvironment(
    'TIKTOK_CLIENT_KEY',
  );
  static const String _tiktokClientSecret = String.fromEnvironment(
    'TIKTOK_CLIENT_SECRET',
  );
  static const String _instagramAppId = String.fromEnvironment(
    'INSTAGRAM_APP_ID',
  );
  static const String _instagramAppSecret = String.fromEnvironment(
    'INSTAGRAM_APP_SECRET',
  );

  static const OAuthClientConfig youtube = OAuthClientConfig(
    clientId: _youtubeClientId,
    clientSecret: _youtubeClientSecret,
    authorizationEndpoint: 'https://accounts.google.com/o/oauth2/v2/auth',
    tokenEndpoint: 'https://oauth2.googleapis.com/token',
    scopes: [
      'https://www.googleapis.com/auth/youtube.upload',
      'https://www.googleapis.com/auth/youtube.readonly',
    ],
  );

  static const OAuthClientConfig tiktok = OAuthClientConfig(
    clientId: _tiktokClientKey,
    clientSecret: _tiktokClientSecret,
    authorizationEndpoint: 'https://www.tiktok.com/v2/auth/authorize/',
    tokenEndpoint: 'https://open.tiktokapis.com/v2/oauth/token/',
    scopes: ['video.publish'],
  );

  static const OAuthClientConfig instagram = OAuthClientConfig(
    clientId: _instagramAppId,
    clientSecret: _instagramAppSecret,
    authorizationEndpoint: 'https://www.instagram.com/oauth/authorize',
    tokenEndpoint: 'https://api.instagram.com/oauth/access_token',
    scopes: ['instagram_business_basic', 'instagram_business_content_publish'],
  );

  static OAuthClientConfig? forTarget(PublishTarget target) {
    return switch (target) {
      PublishTarget.youtubeShort => youtube,
      PublishTarget.tiktok => tiktok,
      PublishTarget.instagramReel => instagram,
    };
  }

  /// Resolves config from `--dart-define` first, then falls back to a local
  /// ignored JSON file during development. Release builds should still prefer
  /// `--dart-define-from-file` so credentials are available wherever the app is
  /// installed.
  static OAuthClientConfig? resolveForTarget(
    PublishTarget target, {
    String localPath = localConfigPath,
  }) {
    final fromEnvironment = forTarget(target);
    if (fromEnvironment == null || fromEnvironment.isConfigured) {
      return fromEnvironment;
    }

    return _fromLocalFile(target, localPath) ?? fromEnvironment;
  }

  static OAuthClientConfig? _fromLocalFile(PublishTarget target, String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) {
        return null;
      }
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return fromJsonForTarget(target, decoded);
    } catch (_) {
      return null;
    }
  }

  static OAuthClientConfig? fromJsonForTarget(
    PublishTarget target,
    Map<String, dynamic> json,
  ) {
    return switch (target) {
      PublishTarget.youtubeShort => OAuthClientConfig(
        clientId: _stringValue(json, 'YOUTUBE_CLIENT_ID'),
        clientSecret: _stringValue(json, 'YOUTUBE_CLIENT_SECRET'),
        authorizationEndpoint: youtube.authorizationEndpoint,
        tokenEndpoint: youtube.tokenEndpoint,
        scopes: youtube.scopes,
      ),
      PublishTarget.tiktok => OAuthClientConfig(
        clientId: _stringValue(json, 'TIKTOK_CLIENT_KEY'),
        clientSecret: _stringValue(json, 'TIKTOK_CLIENT_SECRET'),
        authorizationEndpoint: tiktok.authorizationEndpoint,
        tokenEndpoint: tiktok.tokenEndpoint,
        scopes: tiktok.scopes,
      ),
      PublishTarget.instagramReel => OAuthClientConfig(
        clientId: _stringValue(json, 'INSTAGRAM_APP_ID'),
        clientSecret: _stringValue(json, 'INSTAGRAM_APP_SECRET'),
        authorizationEndpoint: instagram.authorizationEndpoint,
        tokenEndpoint: instagram.tokenEndpoint,
        scopes: instagram.scopes,
      ),
    };
  }

  static String _stringValue(Map<String, dynamic> json, String key) {
    final value = json[key];
    return value is String ? value.trim() : '';
  }
}
