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

      if (tokens == null) {
        _user = null;
        _status = AuthStatus.unauthenticated;
        _errorMessage = null;
        notifyListeners();
        return;
      }

      _user = _applyLocalNickname(await authApi.me());
      _status = AuthStatus.authenticated;
      _errorMessage = null;
      notifyListeners();
    } on ApiException catch (error) {
      debugPrint('AUTH bootstrap api error: ${error.message}');
      await tokenStorage.clear();
      _user = null;
      _status = AuthStatus.unauthenticated;
      _errorMessage = null;
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('AUTH unexpected bootstrap error: $error');
      debugPrint('$stackTrace');
      await tokenStorage.clear();
      _user = null;
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

      _localNickname = await tokenStorage.readNickname();
      _user = _applyLocalNickname(await authApi.me());
      _status = AuthStatus.authenticated;
      _errorMessage = null;
    } on ApiException catch (error) {
      debugPrint('AUTH anonymous api error: ${error.message}');
      await tokenStorage.clear();
      _user = null;
      _status = AuthStatus.unauthenticated;
      _errorMessage = error.message;
    } catch (error, stackTrace) {
      debugPrint('AUTH anonymous unexpected error: $error');
      debugPrint('$stackTrace');
      await tokenStorage.clear();
      _user = null;
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

      _localNickname = await tokenStorage.readNickname();
      _user = _applyLocalNickname(await authApi.me());
      _status = AuthStatus.authenticated;
      _errorMessage = null;
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      await tokenStorage.clear();
      _user = null;
      _status = AuthStatus.unauthenticated;
      _errorMessage = error.message;
    } catch (error, stackTrace) {
      debugPrint('AUTH google unexpected error: $error');
      debugPrint('$stackTrace');
      await tokenStorage.clear();
      _user = null;
      _status = AuthStatus.unauthenticated;
      _errorMessage = 'Google 로그인에 실패했어요. 잠시 후 다시 시도해 주세요.';
    }

    notifyListeners();
    return false;
  }

  Future<bool> signInWithEmail(String email, String password) async {
    _errorMessage = '현재 이메일 로그인은 지원되지 않아요. 익명 또는 Google 로그인을 이용해 주세요.';
    notifyListeners();
    return false;
  }

  Future<bool> signUpWithEmail({
    required String email,
    required String password,
    String? name,
  }) async {
    _errorMessage = '현재 이메일 계정 만들기는 지원되지 않아요. 익명 또는 Google 로그인을 이용해 주세요.';
    notifyListeners();
    return false;
  }

  Future<void> refreshMe() async {
    try {
      _localNickname = await tokenStorage.readNickname();
      _user = _applyLocalNickname(await authApi.me());
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
    _status = AuthStatus.unauthenticated;
    _errorMessage = null;
    notifyListeners();
  }

  AppUser _applyLocalNickname(AppUser user) {
    final nickname = rawNickname(_localNickname ?? '');
    if (nickname.isEmpty) return user;
    return user.copyWith(name: nickname);
  }
}
