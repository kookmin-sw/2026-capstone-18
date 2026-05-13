import 'package:flutter/foundation.dart';

import '../../core/errors/api_exception.dart';
import 'data/consent_api.dart';

class ConsentProvider extends ChangeNotifier {
  final ConsentApi consentApi;

  ConsentState? _consent;
  String? _errorMessage;
  bool _isLoading = false;
  int _sessionVersion = 0;

  ConsentProvider({required this.consentApi});

  ConsentState? get consent => _consent;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _isLoading;

  Future<void> loadConsent() async {
    final requestVersion = ++_sessionVersion;
    _consent = null;
    _errorMessage = null;
    _isLoading = true;
    notifyListeners();

    try {
      final consent = await consentApi.getConsent();
      if (requestVersion != _sessionVersion) return;
      _consent = consent;
      _errorMessage = null;
    } on ApiException catch (error) {
      if (requestVersion != _sessionVersion) return;
      _consent = null;
      _errorMessage = error.message;
    } finally {
      if (requestVersion == _sessionVersion) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> updateConsent(Map<String, dynamic> changes) async {
    final requestVersion = _sessionVersion;
    try {
      final consent = await consentApi.updateConsent(changes);
      if (requestVersion != _sessionVersion) return;
      _consent = consent;
      _errorMessage = null;
    } on ApiException catch (error) {
      if (requestVersion != _sessionVersion) return;
      _errorMessage = error.message;
    }
    notifyListeners();
  }

  void clearSessionData() {
    _sessionVersion += 1;
    _consent = null;
    _errorMessage = null;
    _isLoading = false;
    notifyListeners();
  }
}
