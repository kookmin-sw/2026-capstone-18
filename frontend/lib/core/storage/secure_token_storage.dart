import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthTokens {
  final String accessToken;
  final String refreshToken;

  const AuthTokens({required this.accessToken, required this.refreshToken});

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
    );
  }
}

class SecureTokenStorage {
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _nicknameKey = 'profile_nickname';

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

  Future<void> saveTokens(AuthTokens tokens) async {
    await _storage.write(key: _accessTokenKey, value: tokens.accessToken);
    await _storage.write(key: _refreshTokenKey, value: tokens.refreshToken);
  }

  Future<void> saveNickname(String nickname) async {
    await _storage.write(key: _nicknameKey, value: nickname);
  }

  Future<void> clear() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _nicknameKey);
  }
}
