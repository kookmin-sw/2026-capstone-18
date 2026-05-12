import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_signals/core/network/api_client.dart';
import 'package:little_signals/core/storage/secure_token_storage.dart';
import 'package:little_signals/core/theme/app_theme.dart';
import 'package:little_signals/features/auth/auth_provider.dart';
import 'package:little_signals/features/auth/data/app_user.dart';
import 'package:little_signals/features/auth/data/auth_api.dart';
import 'package:little_signals/features/auth/screens/email_login_screen.dart';
import 'package:little_signals/features/auth/screens/email_register_screen.dart';
import 'package:little_signals/features/auth/screens/login_screen.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('email login shows loading only on the selected action', (
    tester,
  ) async {
    final auth = _LoadingAuthProvider();
    auth.emailLoginCompleter = Completer<bool>();

    await tester.pumpWidget(_authApp(auth, const EmailLoginScreen()));
    await tester.enterText(
      find.widgetWithText(TextFormField, '이메일'),
      'a@b.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '비밀번호'),
      '123456',
    );

    await tester.tap(find.text('이메일로 로그인하기'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Google 계정으로 계속하기'), findsOneWidget);

    auth.emailLoginCompleter!.complete(false);
    await tester.pumpAndSettle();

    auth.googleCompleter = Completer<bool>();
    await tester.tap(find.text('Google 계정으로 계속하기'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('이메일로 로그인하기'), findsOneWidget);

    auth.googleCompleter!.complete(false);
    await tester.pumpAndSettle();
  });

  testWidgets('sign up shows loading only on the selected action', (
    tester,
  ) async {
    final auth = _LoadingAuthProvider();
    auth.emailSignUpCompleter = Completer<bool>();

    await tester.pumpWidget(_authApp(auth, const EmailRegisterScreen()));
    await tester.enterText(
      find.widgetWithText(TextFormField, '이메일'),
      'a@b.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '비밀번호'),
      '123456',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '비밀번호 확인'),
      '123456',
    );

    await tester.tap(find.text('이메일로 계정 만들기'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Google 계정으로 계속하기'), findsOneWidget);

    auth.emailSignUpCompleter!.complete(false);
    await tester.pumpAndSettle();
  });

  testWidgets('anonymous start shows loading only on anonymous action', (
    tester,
  ) async {
    final auth = _LoadingAuthProvider();
    auth.anonymousCompleter = Completer<void>();

    await tester.pumpWidget(_authApp(auth, const LoginScreen()));
    await tester.tap(find.text('익명으로 시작하기'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('시작하기'), findsOneWidget);
    expect(find.text('이미 계정이 있으신가요?'), findsOneWidget);

    auth.anonymousCompleter!.complete();
    await tester.pumpAndSettle();
  });
}

Widget _authApp(AuthProvider auth, Widget child) {
  return ChangeNotifierProvider<AuthProvider>.value(
    value: auth,
    child: MaterialApp(theme: AppTheme.light, home: child),
  );
}

class _LoadingAuthProvider extends AuthProvider {
  Completer<bool>? emailLoginCompleter;
  Completer<bool>? emailSignUpCompleter;
  Completer<bool>? googleCompleter;
  Completer<void>? anonymousCompleter;

  _LoadingAuthProvider()
    : super(
        authApi: AuthApi(apiClient: _dummyApiClient()),
        tokenStorage: SecureTokenStorage(),
        apiClient: _dummyApiClient(),
      );

  @override
  AuthStatus get status => AuthStatus.unauthenticated;

  @override
  AppUser? get user => null;

  @override
  String? get errorMessage => '테스트 오류';

  @override
  Future<bool> signInWithEmail(String email, String password) async {
    return emailLoginCompleter == null ? false : emailLoginCompleter!.future;
  }

  @override
  Future<bool> signUpWithEmail({
    required String email,
    required String password,
    String? name,
  }) async {
    return emailSignUpCompleter == null ? false : emailSignUpCompleter!.future;
  }

  @override
  Future<bool> continueWithGoogle() async {
    return googleCompleter == null ? false : googleCompleter!.future;
  }

  @override
  Future<void> signInAnonymously() async {
    if (anonymousCompleter != null) {
      await anonymousCompleter!.future;
    }
  }
}

ApiClient _dummyApiClient() {
  return ApiClient(tokenStorage: SecureTokenStorage());
}
