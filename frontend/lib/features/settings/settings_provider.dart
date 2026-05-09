import 'package:flutter/foundation.dart';

import '../../core/errors/api_exception.dart';
import 'data/settings_api.dart';

class SettingsProvider extends ChangeNotifier {
  final SettingsApi settingsApi;

  UserSettings? _settings;
  String? _errorMessage;

  SettingsProvider({required this.settingsApi});

  UserSettings? get settings => _settings;
  String? get errorMessage => _errorMessage;

  Future<void> loadSettings() async {
    try {
      _settings = await settingsApi.getSettings();
      _errorMessage = null;
    } on ApiException catch (error) {
      _errorMessage = error.message;
    }
    notifyListeners();
  }

  Future<void> updateSettings(Map<String, dynamic> changes) async {
    try {
      _settings = await settingsApi.updateSettings(changes);
      _errorMessage = null;
    } on ApiException catch (error) {
      _errorMessage = error.message;
    }
    notifyListeners();
  }

  void clearSessionData() {
    _settings = null;
    _errorMessage = null;
    notifyListeners();
  }
}
