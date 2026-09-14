import 'dart:async';
import 'dart:io';

import '../../../domain/publishing/auth/oauth_authenticator.dart';

/// Result of a captured OAuth redirect.
class LoopbackRedirectResult {
  const LoopbackRedirectResult({required this.code, required this.state});

  final String code;
  final String state;
}

/// A one-shot local web server that captures the `?code=&state=` redirect of
/// an installed-app OAuth flow on `http://127.0.0.1:<port>/`.
///
/// Desktop OAuth clients (Google, TikTok) redirect back to a loopback address;
/// this listens on an ephemeral port, hands back the authorization code, and
/// shows the user a small "you can close this tab" page.
class LoopbackRedirectServer {
  LoopbackRedirectServer._(this._server);

  final HttpServer _server;

  int get port => _server.port;

  String get redirectUri => 'http://127.0.0.1:$port/';

  static Future<LoopbackRedirectServer> start({int port = 0}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    return LoopbackRedirectServer._(server);
  }

  /// Waits for the redirect and returns the authorization code. Verifies the
  /// returned `state` matches [expectedState]. Times out after [timeout].
  Future<LoopbackRedirectResult> waitForCode({
    required String expectedState,
    Duration timeout = const Duration(minutes: 15),
  }) async {
    final completer = Completer<LoopbackRedirectResult>();

    final subscription = _server.listen((request) async {
      final params = request.uri.queryParameters;
      final error = params['error'];
      final code = params['code'];
      final state = params['state'];

      final ok = error == null && code != null && state == expectedState;
      await _respond(request, success: ok, error: error);

      if (completer.isCompleted) {
        return;
      }
      if (error != null) {
        completer.completeError(OAuthException('Authorization denied: $error'));
      } else if (code == null) {
        completer.completeError(
          const OAuthException('Authorization response had no code.'),
        );
      } else if (state != expectedState) {
        completer.completeError(
          const OAuthException('Authorization state mismatch.'),
        );
      } else {
        completer.complete(
          LoopbackRedirectResult(code: code, state: expectedState),
        );
      }
    });

    try {
      return await completer.future.timeout(
        timeout,
        onTimeout: () =>
            throw const OAuthException('Timed out waiting for authorization.'),
      );
    } finally {
      await subscription.cancel();
    }
  }

  Future<void> _respond(
    HttpRequest request, {
    required bool success,
    String? error,
  }) async {
    final message = success
        ? 'Authorization complete. You can close this tab and return to '
              'Content Maker.'
        : 'Authorization failed${error == null ? '' : ': $error'}. You can '
              'close this tab and try again in Content Maker.';
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      ..write(
        '<!doctype html><html><head><meta charset="utf-8">'
        '<title>Content Maker</title></head>'
        '<body style="font-family:sans-serif;background:#080808;color:#e8e8e8;'
        'display:flex;align-items:center;justify-content:center;height:100vh;'
        'margin:0"><p style="max-width:28rem;text-align:center">$message</p>'
        '</body></html>',
      );
    await request.response.close();
  }

  Future<void> close() async {
    try {
      await _server.close(force: true);
    } on HttpException {
      // The server may already be closed after a timed-out or abandoned auth
      // attempt. Treat close as idempotent so cleanup does not mask the real
      // OAuth result.
    }
  }
}
