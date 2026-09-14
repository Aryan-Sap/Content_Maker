import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:content_maker/src/domain/publishing/publish_target.dart';
import 'package:content_maker/src/infrastructure/publishing/oauth/oauth_config.dart';

void main() {
  test('OAuth config rejects empty and placeholder values', () {
    const empty = OAuthClientConfig(
      clientId: '',
      clientSecret: '',
      authorizationEndpoint: 'https://example.test/auth',
      tokenEndpoint: 'https://example.test/token',
      scopes: [],
    );
    const placeholder = OAuthClientConfig(
      clientId: 'REPLACE_WITH_CLIENT_ID',
      clientSecret: 'REPLACE_WITH_CLIENT_SECRET',
      authorizationEndpoint: 'https://example.test/auth',
      tokenEndpoint: 'https://example.test/token',
      scopes: [],
    );
    const configured = OAuthClientConfig(
      clientId: 'real-client',
      clientSecret: 'real-secret',
      authorizationEndpoint: 'https://example.test/auth',
      tokenEndpoint: 'https://example.test/token',
      scopes: [],
    );

    expect(empty.isConfigured, isFalse);
    expect(placeholder.isConfigured, isFalse);
    expect(configured.isConfigured, isTrue);
  });

  test('OAuth config reads local JSON values for app development', () {
    final youtube = OAuthConfig.fromJsonForTarget(PublishTarget.youtubeShort, {
      'YOUTUBE_CLIENT_ID': ' desktop.apps.googleusercontent.com ',
      'YOUTUBE_CLIENT_SECRET': ' youtube-secret ',
    });
    final tiktok = OAuthConfig.fromJsonForTarget(PublishTarget.tiktok, {
      'TIKTOK_CLIENT_KEY': ' tiktok-key ',
      'TIKTOK_CLIENT_SECRET': ' tiktok-secret ',
    });
    final instagram =
        OAuthConfig.fromJsonForTarget(PublishTarget.instagramReel, {
          'INSTAGRAM_APP_ID': ' instagram-app-id ',
          'INSTAGRAM_APP_SECRET': ' instagram-app-secret ',
        });

    expect(youtube?.clientId, 'desktop.apps.googleusercontent.com');
    expect(youtube?.clientSecret, 'youtube-secret');
    expect(
      youtube?.scopes,
      contains('https://www.googleapis.com/auth/youtube.upload'),
    );
    expect(tiktok?.clientId, 'tiktok-key');
    expect(tiktok?.clientSecret, 'tiktok-secret');
    expect(tiktok?.scopes, ['video.publish']);
    expect(instagram?.clientId, 'instagram-app-id');
    expect(instagram?.clientSecret, 'instagram-app-secret');
    expect(instagram?.scopes, contains('instagram_business_content_publish'));
  });

  test(
    'OAuth config resolves from local file when dart defines are absent',
    () {
      final tempDir = Directory.systemTemp.createTempSync('oauth-config-test');
      final configPath = '${tempDir.path}${Platform.pathSeparator}oauth.json';
      File(configPath).writeAsStringSync('''
{
  "YOUTUBE_CLIENT_ID": "desktop.apps.googleusercontent.com",
  "YOUTUBE_CLIENT_SECRET": "youtube-secret"
}
''');

      final config = OAuthConfig.resolveForTarget(
        PublishTarget.youtubeShort,
        localPath: configPath,
      );

      expect(config?.clientId, 'desktop.apps.googleusercontent.com');
      expect(config?.clientSecret, 'youtube-secret');

      tempDir.deleteSync(recursive: true);
    },
  );
}
