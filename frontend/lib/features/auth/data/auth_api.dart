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
    return AuthTokens.fromJson(_asMap(response));
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

      return AuthTokens.fromJson(_asMap(response));
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

  Future<AuthTokens> emailLogin(String email, String password) {
    throw const ApiException(
      message: '현재 이메일 로그인은 지원되지 않아요. 익명 또는 Google 로그인을 이용해 주세요.',
    );
  }

  Future<AuthTokens> emailSignUp({
    required String email,
    required String password,
    String? name,
  }) {
    throw const ApiException(
      message: '현재 이메일 계정 만들기는 지원되지 않아요. 익명 또는 Google 로그인을 이용해 주세요.',
    );
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
      serverClientId: _googleServerClientId.isEmpty
          ? null
          : _googleServerClientId,
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
}
