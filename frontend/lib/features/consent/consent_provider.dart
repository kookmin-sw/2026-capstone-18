import 'package:flutter/foundation.dart';

import '../../core/errors/api_exception.dart';
import 'data/consent_api.dart';

class ConsentProvider extends ChangeNotifier {
  final ConsentApi consentApi;

  ConsentState? _consent;
  String? _errorMessage;

  ConsentProvider({required this.consentApi});

  ConsentState? get consent => _consent;
  String? get errorMessage => _errorMessage;

  Future<void> loadConsent() async {
    try {
      _consent = await consentApi.getConsent();
      _errorMessage = null;
    } on ApiException catch (error) {
      _errorMessage = error.message;
    }
    notifyListeners();
  }

  Future<void> updateConsent(Map<String, dynamic> changes) async {
    try {
      _consent = await consentApi.updateConsent(changes);
      _errorMessage = null;
    } on ApiException catch (error) {
      _errorMessage = error.message;
    }
    notifyListeners();
  }

  void clearSessionData() {
    _consent = null;
    _errorMessage = null;
    notifyListeners();
  }
}
