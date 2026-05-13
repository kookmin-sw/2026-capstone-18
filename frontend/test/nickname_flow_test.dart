import 'package:flutter_test/flutter_test.dart';
import 'package:little_signals/core/network/api_client.dart';
import 'package:little_signals/core/storage/secure_token_storage.dart';
import 'package:little_signals/features/auth/auth_provider.dart';
import 'package:little_signals/features/auth/data/app_user.dart';
import 'package:little_signals/features/auth/data/auth_api.dart';
import 'package:little_signals/features/auth/user_display.dart';

void main() {
  test('restores and saves nickname through auth provider storage', () async {
    final storage = _MemoryTokenStorage(
      tokens: const AuthTokens(accessToken: 'access', refreshToken: 'refresh'),
      nickname: '수빈',
    );
    final authApi = _MemoryAuthApi();
    final provider = AuthProvider(
      authApi: authApi,
      tokenStorage: storage,
      apiClient: _dummyApiClient(storage),
    );

    await provider.bootstrap();

    expect(provider.status, AuthStatus.authenticated);
    expect(userDisplayName(provider.user), '수빈');

    final saved = await provider.updateNickname('하린님');

    expect(saved, isTrue);
    expect(storage.nickname, '하린');
    expect(userDisplayName(provider.user), '하린');

    final restarted = AuthProvider(
      authApi: authApi,
      tokenStorage: storage,
      apiClient: _dummyApiClient(storage),
    );

    await restarted.bootstrap();

    expect(restarted.status, AuthStatus.authenticated);
    expect(userDisplayName(restarted.user), '하린');
  });

  test('clears local nickname with session storage', () async {
    final storage = _MemoryTokenStorage(
      tokens: const AuthTokens(accessToken: 'access', refreshToken: 'refresh'),
      nickname: 'ava',
    );
    final provider = AuthProvider(
      authApi: _MemoryAuthApi(),
      tokenStorage: storage,
      apiClient: _dummyApiClient(storage),
    );

    await provider.bootstrap();
    expect(userDisplayName(provider.user), 'ava');

    await provider.logout();

    expect(provider.status, AuthStatus.unauthenticated);
    expect(provider.user, isNull);
    expect(storage.tokens, isNull);
    expect(storage.nickname, isNull);
  });

  test('keeps email account metadata when me response has no email', () async {
    final storage = _MemoryTokenStorage();
    final provider = AuthProvider(
      authApi: _MemoryAuthApi(),
      tokenStorage: storage,
      apiClient: _dummyApiClient(storage),
    );

    final signedIn = await provider.signInWithEmail(
      'user@example.com',
      'hunter2pw',
    );

    expect(signedIn, isTrue);
    expect(provider.user?.accountType, 'email');
    expect(provider.user?.email, 'user@example.com');
    expect(storage.accountType, 'email');
    expect(storage.email, 'user@example.com');
  });
}

class _MemoryTokenStorage extends SecureTokenStorage {
  AuthTokens? tokens;
  String? nickname;
  String? accountType;
  String? email;

  _MemoryTokenStorage({this.tokens, this.nickname});

  @override
  Future<AuthTokens?> readTokens() async => tokens;

  @override
  Future<String?> readAccessToken() async => tokens?.accessToken;

  @override
  Future<String?> readRefreshToken() async => tokens?.refreshToken;

  @override
  Future<String?> readNickname() async => nickname;

  @override
  Future<String?> readAccountType() async => accountType;

  @override
  Future<String?> readAccountEmail() async => email;

  @override
  Future<void> saveTokens(AuthTokens tokens) async {
    this.tokens = tokens;
  }

  @override
  Future<void> saveAccountMetadata({String? accountType, String? email}) async {
    this.accountType = accountType;
    this.email = email;
  }

  @override
  Future<void> saveNickname(String nickname) async {
    this.nickname = nickname;
  }

  @override
  Future<void> clear() async {
    tokens = null;
    nickname = null;
    accountType = null;
    email = null;
  }
}

class _MemoryAuthApi extends AuthApi {
  AppUser user = const AppUser(
    id: 'anonymous-1',
    email: null,
    name: null,
    accountType: 'anonymous',
    consent: <String, dynamic>{},
    settings: <String, dynamic>{},
  );

  _MemoryAuthApi() : super(apiClient: _dummyApiClient());

  @override
  Future<AppUser> me() async => user;

  @override
  Future<AuthTokens> emailLogin(String email, String password) async {
    return AuthTokens(
      accessToken: 'email-access',
      refreshToken: 'email-refresh',
      accountType: 'email',
      email: email,
    );
  }

  @override
  Future<AppUser> updateMe(Map<String, dynamic> changes) async {
    user = user.copyWith(name: changes['display_name'] as String?);
    return user;
  }

  @override
  Future<void> logout() async {}
}

ApiClient _dummyApiClient([SecureTokenStorage? storage]) {
  return ApiClient(tokenStorage: storage ?? SecureTokenStorage());
}
