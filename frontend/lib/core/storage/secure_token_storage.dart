import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthTokens {
  final String accessToken;
  final String refreshToken;
  final String? accountType;
  final String? email;

  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    this.accountType,
    this.email,
  });

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    final accessToken =
        json['access_token'] ??
        json['accessToken'] ??
        json['token'] ??
        json['jwt'];
    final refreshToken =
        json['refresh_token'] ?? json['refreshToken'] ?? json['refresh'] ?? '';

    if (accessToken is! String || accessToken.isEmpty) {
      throw const FormatException('로그인 정보를 확인하지 못했어요.');
    }

    return AuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken is String ? refreshToken : '',
      accountType: json['is_anonymous'] == true
          ? 'anonymous'
          : json['account_type'] as String?,
      email: json['email'] as String?,
    );
  }

  AuthTokens copyWith({String? accountType, String? email}) {
    return AuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      accountType: accountType ?? this.accountType,
      email: email ?? this.email,
    );
  }
}

class SecureTokenStorage {
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _nicknameKey = 'profile_nickname';
  static const _accountTypeKey = 'auth_account_type';
  static const _accountEmailKey = 'auth_account_email';

  final FlutterSecureStorage _storage;

  SecureTokenStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  Future<String?> readAccessToken() {
    return _storage.read(key: _accessTokenKey);
  }

  Future<String?> readRefreshToken() {
    return _storage.read(key: _refreshTokenKey);
  }

  Future<AuthTokens?> readTokens() async {
    final accessToken = await readAccessToken();
    final refreshToken = await readRefreshToken();

    if (accessToken == null || refreshToken == null) return null;

    return AuthTokens(accessToken: accessToken, refreshToken: refreshToken);
  }

  Future<String?> readNickname() {
    return _storage.read(key: _nicknameKey);
  }

  Future<String?> readAccountType() {
    return _storage.read(key: _accountTypeKey);
  }

  Future<String?> readAccountEmail() {
    return _storage.read(key: _accountEmailKey);
  }

  Future<void> saveTokens(AuthTokens tokens) async {
    await _storage.write(key: _accessTokenKey, value: tokens.accessToken);
    await _storage.write(key: _refreshTokenKey, value: tokens.refreshToken);
  }

  Future<void> saveAccountMetadata({String? accountType, String? email}) async {
    final normalizedType = accountType?.trim();
    if (normalizedType == null || normalizedType.isEmpty) {
      await _storage.delete(key: _accountTypeKey);
    } else {
      await _storage.write(key: _accountTypeKey, value: normalizedType);
    }

    final normalizedEmail = email?.trim();
    if (normalizedEmail == null || normalizedEmail.isEmpty) {
      await _storage.delete(key: _accountEmailKey);
    } else {
      await _storage.write(key: _accountEmailKey, value: normalizedEmail);
    }
  }

  Future<void> saveNickname(String nickname) async {
    await _storage.write(key: _nicknameKey, value: nickname);
  }

  Future<void> clear() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _nicknameKey);
    await _storage.delete(key: _accountTypeKey);
    await _storage.delete(key: _accountEmailKey);
  }
}
