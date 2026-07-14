import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// A PKCE (RFC 7636) verifier/challenge pair.
///
/// TikTok requires PKCE for its OAuth v2 flow; Google supports it for desktop
/// clients. Both use the `S256` challenge method.
class PkcePair {
  const PkcePair({required this.verifier, required this.challenge});

  final String verifier;
  final String challenge;

  static const String challengeMethod = 'S256';

  /// Generates a random verifier and its base64url-encoded SHA-256 challenge.
  factory PkcePair.generate([Random? random]) {
    final rng = random ?? Random.secure();
    final verifier = _randomUrlToken(rng, 64);
    final digest = sha256.convert(ascii.encode(verifier));
    final challenge = _base64UrlNoPadding(digest.bytes);
    return PkcePair(verifier: verifier, challenge: challenge);
  }

  static String _randomUrlToken(Random rng, int length) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    return List.generate(
      length,
      (_) => chars[rng.nextInt(chars.length)],
    ).join();
  }

  static String _base64UrlNoPadding(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}

/// Random opaque `state` value used to defend against CSRF on the redirect.
String generateOAuthState([Random? random]) {
  final rng = random ?? Random.secure();
  final bytes = List<int>.generate(24, (_) => rng.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}
