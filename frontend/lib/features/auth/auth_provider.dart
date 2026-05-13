import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/utils/korean_ui_text.dart';
import '../../core/errors/api_exception.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/secure_token_storage.dart';
import 'data/app_user.dart';
import 'data/auth_api.dart';

enum AuthStatus { checking, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  final AuthApi authApi;
  final SecureTokenStorage tokenStorage;
  final ApiClient apiClient;

  AuthStatus _status = AuthStatus.checking;
  AppUser? _user;
  String? _errorMessage;
  String? _localNickname;
  String? _sessionAccountType;
  String? _sessionEmail;

  AuthProvider({
    required this.authApi,
    required this.tokenStorage,
    required this.apiClient,
  }) {
    apiClient.onUnauthorized = _handleUnauthorized;
  }

  AuthStatus get status => _status;
  AppUser? get user => _user;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _status == AuthStatus.authenticated;

  Future<void> bootstrap() async {
    _status = AuthStatus.checking;
    _errorMessage = null;
    notifyListeners();

    try {
      _localNickname = await tokenStorage.readNickname();
      final tokens = await tokenStorage.readTokens().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          debugPrint('AUTH token read timed out; treating as no token');
          return null;
        },
      );

      await _restoreSessionMetadata(tokens);
      if (tokens == null) {
        _user = null;
        _sessionAccountType = null;
        _sessionEmail = null;
        _status = AuthStatus.unauthenticated;
        _errorMessage = null;
        notifyListeners();
        return;
      }

      _user = _applySessionMetadata(_applyLocalNickname(await authApi.me()));
      _status = AuthStatus.authenticated;
      _errorMessage = null;
      notifyListeners();
    } on ApiException catch (error) {
      debugPrint('AUTH bootstrap api error: ${error.message}');
      await tokenStorage.clear();
      _user = null;
      _sessionAccountType = null;
      _sessionEmail = null;
      _status = AuthStatus.unauthenticated;
      _errorMessage = null;
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('AUTH unexpected bootstrap error: $error');
      debugPrint('$stackTrace');
      await tokenStorage.clear();
      _user = null;
      _sessionAccountType = null;
      _sessionEmail = null;
      _status = AuthStatus.unauthenticated;
      _errorMessage = '로그인 상태를 확인하지 못했어요. 다시 로그인해 주세요.';
      notifyListeners();
    }
  }

  Future<void> signInAnonymously() async {
    _status = AuthStatus.checking;
    _errorMessage = null;
    notifyListeners();

    try {
      final tokens = await authApi.anonymousLogin().timeout(
        const Duration(seconds: 20),
      );
      await tokenStorage.saveTokens(tokens);
      await _saveSessionMetadata(tokens, fallbackType: 'anonymous');

      _localNickname = await tokenStorage.readNickname();
      _user = _applySessionMetadata(_applyLocalNickname(await authApi.me()));
      _status = AuthStatus.authenticated;
      _errorMessage = null;
    } on ApiException catch (error) {
      debugPrint('AUTH anonymous api error: ${error.message}');
      await tokenStorage.clear();
      _user = null;
      _sessionAccountType = null;
      _sessionEmail = null;
      _status = AuthStatus.unauthenticated;
      _errorMessage = error.message;
    } catch (error, stackTrace) {
      debugPrint('AUTH anonymous unexpected error: $error');
      debugPrint('$stackTrace');
      await tokenStorage.clear();
      _user = null;
      _sessionAccountType = null;
      _sessionEmail = null;
      _status = AuthStatus.unauthenticated;
      _errorMessage = '익명으로 시작하지 못했어요. 잠시 후 다시 시도해 주세요.';
    }

    notifyListeners();
  }

  Future<bool> continueWithGoogle() async {
    _status = AuthStatus.checking;
    _errorMessage = null;
    notifyListeners();

    try {
      final tokens = await authApi.googleLogin();
      await tokenStorage.saveTokens(tokens);
      await _saveSessionMetadata(tokens, fallbackType: 'google');

      _localNickname = await tokenStorage.readNickname();
      _user = _applySessionMetadata(_applyLocalNickname(await authApi.me()));
      _status = AuthStatus.authenticated;
      _errorMessage = null;
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      await tokenStorage.clear();
      _user = null;
      _sessionAccountType = null;
      _sessionEmail = null;
      _status = AuthStatus.unauthenticated;
      _errorMessage = error.message;
    } catch (error, stackTrace) {
      debugPrint('AUTH google unexpected error: $error');
      debugPrint('$stackTrace');
      await tokenStorage.clear();
      _user = null;
      _sessionAccountType = null;
      _sessionEmail = null;
      _status = AuthStatus.unauthenticated;
      _errorMessage = 'Google 로그인에 실패했어요. 잠시 후 다시 시도해 주세요.';
    }

    notifyListeners();
    return false;
  }

  Future<bool> signInWithEmail(String email, String password) async {
    _status = AuthStatus.checking;
    _errorMessage = null;
    notifyListeners();

    try {
      final tokens = await authApi.emailLogin(email, password);
      await tokenStorage.saveTokens(tokens);
      await _saveSessionMetadata(tokens, fallbackType: 'email');

      _localNickname = await tokenStorage.readNickname();
      _user = _applySessionMetadata(_applyLocalNickname(await authApi.me()));
      _status = AuthStatus.authenticated;
      _errorMessage = null;
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      await tokenStorage.clear();
      _user = null;
      _sessionAccountType = null;
      _sessionEmail = null;
      _status = AuthStatus.unauthenticated;
      _errorMessage = error.message;
    } catch (error, stackTrace) {
      debugPrint('AUTH email login unexpected error: $error');
      debugPrint('$stackTrace');
      await tokenStorage.clear();
      _user = null;
      _sessionAccountType = null;
      _sessionEmail = null;
      _status = AuthStatus.unauthenticated;
      _errorMessage = '로그인하지 못했어요. 잠시 후 다시 시도해 주세요.';
    }

    notifyListeners();
    return false;
  }

  Future<bool> signUpWithEmail({
    required String email,
    required String password,
    String? name,
  }) async {
    _status = AuthStatus.checking;
    _errorMessage = null;
    notifyListeners();

    try {
      final tokens = await authApi.emailSignUp(
        email: email,
        password: password,
        name: name,
      );
      await tokenStorage.saveTokens(tokens);
      await _saveSessionMetadata(tokens, fallbackType: 'email');

      _localNickname = await tokenStorage.readNickname();
      _user = _applySessionMetadata(_applyLocalNickname(await authApi.me()));
      _status = AuthStatus.authenticated;
      _errorMessage = null;
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      await tokenStorage.clear();
      _user = null;
      _sessionAccountType = null;
      _sessionEmail = null;
      _status = AuthStatus.unauthenticated;
      _errorMessage = error.message;
    } catch (error, stackTrace) {
      debugPrint('AUTH email signup unexpected error: $error');
      debugPrint('$stackTrace');
      await tokenStorage.clear();
      _user = null;
      _sessionAccountType = null;
      _sessionEmail = null;
      _status = AuthStatus.unauthenticated;
      _errorMessage = '계정을 만들지 못했어요. 잠시 후 다시 시도해 주세요.';
    }

    notifyListeners();
    return false;
  }

  Future<void> refreshMe() async {
    try {
      _localNickname = await tokenStorage.readNickname();
      _user = _applySessionMetadata(_applyLocalNickname(await authApi.me()));
      _errorMessage = null;
      notifyListeners();
    } on ApiException catch (error) {
      _errorMessage = error.message;
      notifyListeners();
    }
  }

  Future<bool> updateNickname(String nickname) async {
    final normalized = rawNickname(nickname);
    if (normalized.isEmpty) {
      _errorMessage = '닉네임을 입력해 주세요.';
      notifyListeners();
      return false;
    }

    try {
      await tokenStorage.saveNickname(normalized);
      _localNickname = normalized;
      if (_user != null) {
        _user = _user!.copyWith(name: normalized);
      }
      _errorMessage = null;
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('AUTH nickname local save failed: $error');
      debugPrint('$stackTrace');
      _errorMessage = '닉네임을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.';
      notifyListeners();
      return false;
    }

    if (_status == AuthStatus.authenticated) {
      try {
        final updated = await authApi.updateMe({'display_name': normalized});
        _user = updated.copyWith(name: normalized);
        _errorMessage = null;
        notifyListeners();
      } catch (error, stackTrace) {
        debugPrint('AUTH nickname remote update skipped: $error');
        debugPrint('$stackTrace');
      }
    }

    return true;
  }

  Future<void> logout() async {
    try {
      await authApi.logout();
    } catch (error, stackTrace) {
      debugPrint('AUTH logout api error: $error');
      debugPrint('$stackTrace');
    }

    try {
      await authApi.signOutFromGoogle();
    } catch (error, stackTrace) {
      debugPrint('AUTH google sign out error: $error');
      debugPrint('$stackTrace');
    }

    await _clearSession();
  }

  Future<void> _handleUnauthorized() async {
    await _clearSession();
  }

  Future<void> _clearSession() async {
    await tokenStorage.clear();
    _user = null;
    _localNickname = null;
    _sessionAccountType = null;
    _sessionEmail = null;
    _status = AuthStatus.unauthenticated;
    _errorMessage = null;
    notifyListeners();
  }

  AppUser _applyLocalNickname(AppUser user) {
    final nickname = rawNickname(_localNickname ?? '');
    if (nickname.isEmpty) return user;
    return user.copyWith(name: nickname);
  }

  Future<void> _restoreSessionMetadata(AuthTokens? tokens) async {
    _sessionAccountType = await tokenStorage.readAccountType();
    _sessionEmail = await tokenStorage.readAccountEmail();

    final claimsMetadata = _sessionMetadataFromToken(tokens?.accessToken);
    _sessionAccountType ??= claimsMetadata.accountType;
    _sessionEmail ??= claimsMetadata.email;
  }

  Future<void> _saveSessionMetadata(
    AuthTokens tokens, {
    required String fallbackType,
  }) async {
    final claimsMetadata = _sessionMetadataFromToken(tokens.accessToken);
    _sessionAccountType =
        tokens.accountType ?? claimsMetadata.accountType ?? fallbackType;
    _sessionEmail = tokens.email ?? claimsMetadata.email;
    await tokenStorage.saveAccountMetadata(
      accountType: _sessionAccountType,
      email: _sessionEmail,
    );
  }

  AppUser _applySessionMetadata(AppUser user) {
    final accountType =
        _normalizeAccountType(_sessionAccountType) ??
        _normalizeAccountType(user.accountType) ??
        'anonymous';
    final email = _trimmedOrNull(user.email) ?? _trimmedOrNull(_sessionEmail);
    return user.copyWith(accountType: accountType, email: email);
  }

  _SessionMetadata _sessionMetadataFromToken(String? token) {
    if (token == null || token.isEmpty) return const _SessionMetadata();

    try {
      final parts = token.split('.');
      if (parts.length < 2) return const _SessionMetadata();
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is! Map<String, dynamic>) return const _SessionMetadata();

      final isAnonymous = payload['is_anonymous'] == true;
      final email = _trimmedOrNull(payload['email'] as String?);
      final appMetadata = payload['app_metadata'];
      final provider = appMetadata is Map<String, dynamic>
          ? _trimmedOrNull(appMetadata['provider'] as String?)
          : null;
      final providers = appMetadata is Map<String, dynamic>
          ? appMetadata['providers']
          : null;
      final hasGoogleProvider =
          provider == 'google' ||
          (providers is List && providers.map((e) => '$e').contains('google'));

      final accountType = isAnonymous
          ? 'anonymous'
          : hasGoogleProvider
          ? 'google'
          : email != null
          ? 'email'
          : null;
      return _SessionMetadata(accountType: accountType, email: email);
    } catch (_) {
      return const _SessionMetadata();
    }
  }

  String? _normalizeAccountType(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    if (normalized == 'anonymous' || normalized == 'anon') return 'anonymous';
    if (normalized == 'google') return 'google';
    if (normalized == 'email' || normalized == 'password') return 'email';
    return null;
  }

  String? _trimmedOrNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }
}

class _SessionMetadata {
  final String? accountType;
  final String? email;

  const _SessionMetadata({this.accountType, this.email});
}
