import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:content_maker/src/infrastructure/publishing/oauth/loopback_redirect_server.dart';

void main() {
  test('captures redirect code and close is idempotent', () async {
    final server = await LoopbackRedirectServer.start();
    final redirectUri = server.redirectUri;

    final wait = server.waitForCode(
      expectedState: 'state',
      timeout: const Duration(seconds: 5),
    );

    final response = await HttpClient()
        .getUrl(Uri.parse('$redirectUri?code=abc&state=state'))
        .then((request) => request.close());
    await response.drain<void>();

    final result = await wait;
    expect(result.code, 'abc');
    expect(redirectUri, startsWith('http://127.0.0.1:'));

    await server.close();
    await server.close();
  });
}
