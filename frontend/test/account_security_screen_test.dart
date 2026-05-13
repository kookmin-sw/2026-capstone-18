import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_signals/core/network/api_client.dart';
import 'package:little_signals/core/storage/secure_token_storage.dart';
import 'package:little_signals/features/auth/auth_provider.dart';
import 'package:little_signals/features/auth/data/app_user.dart';
import 'package:little_signals/features/auth/data/auth_api.dart';
import 'package:little_signals/screens/my/account_security_screen.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
    'email login metadata is visible immediately in account security',
    (tester) async {
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

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: provider,
          child: const MaterialApp(home: AccountSecurityScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('user@example.com'), findsOneWidget);
      expect(find.text('이메일 로그인'), findsOneWidget);
      expect(find.text('계정 정보를 불러올 수 없어요'), findsNothing);
      expect(find.text('익명 계정은 이메일과 비밀번호가 연결되어 있지 않습니다.'), findsNothing);
    },
  );
}

class _MemoryTokenStorage extends SecureTokenStorage {
  AuthTokens? tokens;
  String? accountType;
  String? email;

  @override
  Future<AuthTokens?> readTokens() async => tokens;

  @override
  Future<String?> readAccessToken() async => tokens?.accessToken;

  @override
  Future<String?> readRefreshToken() async => tokens?.refreshToken;

  @override
  Future<String?> readNickname() async => null;

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
  Future<void> clear() async {
    tokens = null;
    accountType = null;
    email = null;
  }
}

class _MemoryAuthApi extends AuthApi {
  _MemoryAuthApi() : super(apiClient: _dummyApiClient());

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
  Future<AppUser> me() async {
    return const AppUser(
      id: 'user-1',
      email: null,
      name: '민지',
      accountType: 'anonymous',
      consent: <String, dynamic>{},
      settings: <String, dynamic>{},
    );
  }
}

ApiClient _dummyApiClient([SecureTokenStorage? storage]) {
  return ApiClient(tokenStorage: storage ?? SecureTokenStorage());
}
