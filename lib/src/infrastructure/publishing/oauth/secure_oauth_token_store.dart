import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../domain/publishing/auth/oauth_credentials.dart';
import '../../../domain/publishing/auth/oauth_token_store.dart';
import '../../../domain/publishing/publish_target.dart';

/// Stores OAuth credentials in the OS secure store (Windows DPAPI, Android
/// Keystore, Keychain on Apple platforms).
class SecureOAuthTokenStore implements OAuthTokenStore {
  const SecureOAuthTokenStore({
    this.storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    ),
  });

  final FlutterSecureStorage storage;

  String _keyFor(PublishTarget target) => 'oauth_${target.storageKey}';

  @override
  Future<OAuthCredentials?> read(PublishTarget target) async {
    final raw = await storage.read(key: _keyFor(target));
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final credentials = OAuthCredentials.fromJson(json);
      return credentials.accessToken.isEmpty ? null : credentials;
    } catch (_) {
      // Corrupt entry: drop it so the user can reconnect cleanly.
      await delete(target);
      return null;
    }
  }

  @override
  Future<void> write(PublishTarget target, OAuthCredentials credentials) {
    return storage.write(
      key: _keyFor(target),
      value: jsonEncode(credentials.toJson()),
    );
  }

  @override
  Future<void> delete(PublishTarget target) {
    return storage.delete(key: _keyFor(target));
  }
}
