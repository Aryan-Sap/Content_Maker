import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:content_maker/src/infrastructure/publishing/instagram/instagram_oauth_authenticator.dart';
import 'package:content_maker/src/infrastructure/publishing/oauth/authorization_code_flow.dart';
import 'package:content_maker/src/infrastructure/publishing/oauth/oauth_config.dart';

void main() {
  const config = OAuthClientConfig(
    clientId: 'instagram-app-id',
    clientSecret: 'instagram-app-secret',
    authorizationEndpoint: 'https://www.instagram.com/oauth/authorize',
    tokenEndpoint: 'https://api.instagram.com/oauth/access_token',
    scopes: ['instagram_business_basic', 'instagram_business_content_publish'],
  );

  test(
    'connects a professional Instagram account with a long-lived token',
    () async {
      final flow = _FakeAuthorizationCodeFlow();
      final client = MockClient((request) async {
        if (request.url.host == 'api.instagram.com') {
          expect(request.method, 'POST');
          expect(request.url.path, '/oauth/access_token');
          return http.Response(
            '{"access_token":"short-token","user_id":123}',
            200,
          );
        }
        if (request.url.path == '/access_token') {
          expect(
            request.url.queryParameters['grant_type'],
            'ig_exchange_token',
          );
          return http.Response(
            '{"access_token":"long-token","expires_in":5184000}',
            200,
          );
        }
        if (request.url.path == '/me') {
          return http.Response('{"id":"123","username":"creator"}', 200);
        }
        return http.Response('not found', 404);
      });

      final credentials = await InstagramOAuthAuthenticator(
        client: client,
        flow: flow,
        config: config,
      ).authorize();

      expect(credentials.accessToken, 'long-token');
      expect(credentials.refreshToken, 'long-token');
      expect(credentials.accountName, '@creator');
      expect(flow.loopbackPort, InstagramOAuthAuthenticator.loopbackPort);
      expect(
        flow.authorizationUrl?.queryParameters['scope'],
        'instagram_business_basic,instagram_business_content_publish',
      );
    },
  );
}

class _FakeAuthorizationCodeFlow implements AuthorizationCodeFlow {
  Uri? authorizationUrl;
  int? loopbackPort;

  @override
  Future<AuthorizationCodeResult> obtainCode({
    required Uri Function({
      required String redirectUri,
      required String codeChallenge,
      required String state,
    })
    buildAuthorizationUrl,
    Duration timeout = const Duration(minutes: 15),
    int loopbackPort = 0,
  }) async {
    this.loopbackPort = loopbackPort;
    authorizationUrl = buildAuthorizationUrl(
      redirectUri: InstagramOAuthAuthenticator.redirectUri,
      codeChallenge: 'unused-challenge',
      state: 'state',
    );
    return const AuthorizationCodeResult(
      code: 'authorization-code',
      redirectUri: InstagramOAuthAuthenticator.redirectUri,
      codeVerifier: 'unused-verifier',
    );
  }
}
