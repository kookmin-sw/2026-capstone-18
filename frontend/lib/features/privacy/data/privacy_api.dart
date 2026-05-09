import '../../../core/network/api_client.dart';

class PrivacyApi {
  final ApiClient _apiClient;

  const PrivacyApi({required ApiClient apiClient}) : _apiClient = apiClient;

  Future<dynamic> exportMyData() {
    return _apiClient.get('/api/v1/sync/download');
  }

  Future<void> deleteAccount() async {
    await _apiClient.delete('/api/v1/account');
  }

  Future<void> restoreAccount() async {
    await _apiClient.post('/api/v1/account/restore');
  }

  Future<dynamic> updatePrivacyConsent(Map<String, dynamic> changes) {
    return _apiClient.patch('/api/v1/consent', body: _toConsentBody(changes));
  }

  Future<dynamic> createBackupUrl(Map<String, dynamic> payload) {
    return _apiClient.post('/api/v1/sync/upload', body: payload);
  }

  Future<void> wipeSyncData() async {
    await _apiClient.delete('/api/v1/sync');
  }

  Map<String, dynamic> _toConsentBody(Map<String, dynamic> changes) {
    return {
      if (changes.containsKey('consent_raw_biosignals'))
        'consent_raw_biosignals': changes['consent_raw_biosignals'],
      if (changes.containsKey('raw_biosignal_consent'))
        'consent_raw_biosignals': changes['raw_biosignal_consent'],
      if (changes.containsKey('consent_audit_logging'))
        'consent_audit_logging': changes['consent_audit_logging'],
      if (changes.containsKey('audit_logging_consent'))
        'consent_audit_logging': changes['audit_logging_consent'],
    };
  }
}
