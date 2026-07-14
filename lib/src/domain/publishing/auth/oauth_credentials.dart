/// OAuth 2.0 tokens for one connected platform account.
class OAuthCredentials {
  const OAuthCredentials({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
    this.scopes = const [],
    this.accountName,
  });

  final String accessToken;

  /// Long-lived token used to mint fresh access tokens without a new login.
  final String? refreshToken;

  /// Absolute expiry of [accessToken]. Null means unknown/non-expiring.
  final DateTime? expiresAt;

  final List<String> scopes;

  /// Display name of the connected account, when resolved.
  final String? accountName;

  /// Treats tokens as expired a minute early so refresh happens before a call.
  bool get isExpired {
    final expiry = expiresAt;
    if (expiry == null) {
      return false;
    }
    return DateTime.now().isAfter(
      expiry.subtract(const Duration(seconds: 60)),
    );
  }

  bool get canRefresh => (refreshToken ?? '').isNotEmpty;

  OAuthCredentials copyWith({
    String? accessToken,
    String? refreshToken,
    DateTime? expiresAt,
    List<String>? scopes,
    String? accountName,
  }) {
    return OAuthCredentials(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      expiresAt: expiresAt ?? this.expiresAt,
      scopes: scopes ?? this.scopes,
      accountName: accountName ?? this.accountName,
    );
  }

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt?.toIso8601String(),
    'scopes': scopes,
    'accountName': accountName,
  };

  factory OAuthCredentials.fromJson(Map<String, dynamic> json) {
    final expiresAt = json['expiresAt'] as String?;
    return OAuthCredentials(
      accessToken: json['accessToken'] as String? ?? '',
      refreshToken: json['refreshToken'] as String?,
      expiresAt: expiresAt == null ? null : DateTime.tryParse(expiresAt),
      scopes:
          (json['scopes'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      accountName: json['accountName'] as String?,
    );
  }
}
