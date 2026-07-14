import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:content_maker/src/infrastructure/publishing/oauth/pkce.dart';

void main() {
  test('challenge is the base64url S256 hash of the verifier, no padding', () {
    final pair = PkcePair.generate();

    final expected = base64Url
        .encode(sha256.convert(ascii.encode(pair.verifier)).bytes)
        .replaceAll('=', '');

    expect(pair.challenge, expected);
    expect(pair.challenge, isNot(contains('=')));
    expect(PkcePair.challengeMethod, 'S256');
  });

  test('generates distinct verifiers', () {
    expect(PkcePair.generate().verifier, isNot(PkcePair.generate().verifier));
  });
}
