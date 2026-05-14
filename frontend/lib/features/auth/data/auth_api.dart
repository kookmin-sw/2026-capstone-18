import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_token_storage.dart';
import 'app_user.dart';

class AuthApi {
  static const googleConfigurationIncompleteMessage =
      'Google 로그인 설정을 다시 확인해 주세요.';

  final ApiClient _apiClient;
  final GoogleSignIn _googleSignIn;
  bool _googleInitialized = false;

  static const _googleServerClientId = String.fromEnvironment(
    'LITTLESIGNALS_GOOGLE_SERVER_CLIENT_ID',
  );

  AuthApi({required ApiClient apiClient, GoogleSignIn? googleSignIn})
    : _apiClient = apiClient,
      _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  Future<AuthTokens> anonymousLogin() async {
    final response = await _apiClient.post('/api/v1/auth/anon', auth: false);
    return AuthTokens.fromJson(
      _asMap(response),
    ).copyWith(accountType: 'anonymous');
  }

  Future<AuthTokens> googleLogin() async {
    try {
      await _initializeGoogleSignIn();

      if (!_googleSignIn.supportsAuthenticate()) {
        throw const ApiException(message: '이 기기에서는 Google 로그인 화면을 열 수 없어요.');
      }

      final account = await _googleSignIn.authenticate(scopeHint: ['email']);
      final auth = account.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const ApiException(message: 'Google 로그인 정보를 확인하지 못했어요.');
      }

      final response = await _apiClient.post(
        '/api/v1/auth/google',
        body: {'id_token': idToken},
        auth: false,
      );

      return AuthTokens.fromJson(
        _asMap(response),
      ).copyWith(accountType: 'google', email: account.email);
    } on ApiException catch (error) {
      if (_isInvalidGoogleToken(error)) {
        throw ApiException(
          statusCode: error.statusCode,
          message: 'Google 로그인 정보를 확인하지 못했어요.',
          details: error.details,
        );
      }
      rethrow;
    } on GoogleSignInException catch (error) {
      throw ApiException(
        message: _googleSignInErrorMessage(error),
        details: error,
      );
    }
  }

  Future<AuthTokens> emailLogin(String email, String password) async {
    try {
      final response = await _apiClient.post(
        '/api/v1/auth/email/login',
        body: {'email': email, 'password': password},
        auth: false,
      );
      return AuthTokens.fromJson(
        _asMap(response),
      ).copyWith(accountType: 'email', email: email);
    } on ApiException catch (error) {
      throw _mapEmailAuthError(error, fallback: '로그인하지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  Future<AuthTokens> emailSignUp({
    required String email,
    required String password,
    String? name,
  }) async {
    try {
      final response = await _apiClient.post(
        '/api/v1/auth/email/signup',
        body: {
          'email': email,
          'password': password,
          if (name != null && name.isNotEmpty) 'display_name': name,
        },
        auth: false,
      );
      return AuthTokens.fromJson(
        _asMap(response),
      ).copyWith(accountType: 'email', email: email);
    } on ApiException catch (error) {
      throw _mapEmailAuthError(
        error,
        fallback: '계정을 만들지 못했어요. 잠시 후 다시 시도해 주세요.',
      );
    }
  }

  Future<void> forgotPassword(String email) async {
    // Backend always returns 200 to defend against account enumeration,
    // so this call effectively cannot fail on the happy/unknown paths.
    // Network/5xx errors still throw ApiException — caller decides how
    // to message them.
    try {
      await _apiClient.post(
        '/api/v1/auth/password/forgot',
        body: {'email': email},
        auth: false,
      );
    } on ApiException catch (error) {
      throw _mapEmailAuthError(
        error,
        fallback: '잠시 후 다시 시도해 주세요.',
      );
    }
  }

  Future<AuthTokens> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    try {
      final response = await _apiClient.post(
        '/api/v1/auth/password/reset',
        body: {
          'email': email,
          'otp': otp,
          'new_password': newPassword,
        },
        auth: false,
      );
      return AuthTokens.fromJson(
        _asMap(response),
      ).copyWith(accountType: 'email', email: email);
    } on ApiException catch (error) {
      throw _mapEmailAuthError(
        error,
        fallback: '비밀번호를 변경하지 못했어요. 잠시 후 다시 시도해 주세요.',
      );
    }
  }

  Future<AppUser> me() async {
    final response = await _apiClient.get('/api/v1/me');
    return AppUser.fromJson(_asMap(response));
  }

  Future<AppUser> updateMe(Map<String, dynamic> changes) async {
    final response = await _apiClient.patch(
      '/api/v1/me',
      body: {
        if (changes.containsKey('display_name'))
          'display_name': changes['display_name'],
      },
    );
    return AppUser.fromJson(_asMap(response));
  }

  Future<void> logout() async {
    await _apiClient.post('/api/v1/auth/logout');
  }

  Future<void> signOutFromGoogle() async {
    if (!_googleInitialized) return;
    await _googleSignIn.signOut();
  }

  Future<void> _initializeGoogleSignIn() async {
    if (_googleInitialized) return;

    await _googleSignIn.initialize(
      clientId: _googleServerClientId.isEmpty ? null : _googleServerClientId,
      serverClientId: kIsWeb
          ? null
          : (_googleServerClientId.isEmpty ? null : _googleServerClientId),
    );
    _googleInitialized = true;
  }

  String _googleSignInErrorMessage(GoogleSignInException error) {
    return switch (error.code) {
      GoogleSignInExceptionCode.canceled => 'Google 로그인이 취소됐어요.',
      GoogleSignInExceptionCode.clientConfigurationError ||
      GoogleSignInExceptionCode.providerConfigurationError =>
        googleConfigurationIncompleteMessage,
      GoogleSignInExceptionCode.uiUnavailable =>
        'Google 로그인 화면을 열 수 없어요. 기기 설정을 한 번 확인해 주세요.',
      GoogleSignInExceptionCode.interrupted => 'Google 로그인이 중단됐어요. 다시 시도해 주세요.',
      _ => 'Google 로그인에 실패했어요. 잠시 후 다시 시도해 주세요.',
    };
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    throw const ApiException(message: '요청 결과를 확인하지 못했어요.');
  }

  bool _isInvalidGoogleToken(ApiException error) {
    if (error.statusCode != 401) return false;

    final details = error.details;
    if (details is Map<String, dynamic>) {
      return details['reason'] == 'invalid_google_token';
    }

    return error.message == 'invalid_google_token';
  }

  ApiException _mapEmailAuthError(
    ApiException error, {
    required String fallback,
  }) {
    final reason = _extractReason(error.details);
    final message = switch (reason) {
      'email_in_use' => '이미 사용 중인 이메일이에요.',
      'invalid_email_credentials' => '이메일이나 비밀번호를 확인해 주세요.',
      'signup_disabled' => '지금은 새 계정을 만들 수 없어요.',
      _ => fallback,
    };
    return ApiException(
      statusCode: error.statusCode,
      message: message,
      details: error.details,
    );
  }

  String? _extractReason(dynamic details) {
    if (details is Map<String, dynamic>) {
      final reason = details['reason'];
      if (reason is String) return reason;
    }
    return null;
  }
}
