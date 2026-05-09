import '../../../core/errors/api_exception.dart';
import '../../../core/network/api_client.dart';

class ConsentState {
  final bool rawBiosignalConsent;
  final bool auditLoggingConsent;
  final DateTime? consentRevokedAt;
  final String privacyPolicyVersion;

  const ConsentState({
    required this.rawBiosignalConsent,
    required this.auditLoggingConsent,
    this.consentRevokedAt,
    required this.privacyPolicyVersion,
  });

  factory ConsentState.fromJson(Map<String, dynamic> json) {
    return ConsentState(
      rawBiosignalConsent:
          json['consent_raw_biosignals'] == true ||
          json['raw_biosignal_consent'] == true,
      auditLoggingConsent:
          json['consent_audit_logging'] == true ||
          json['audit_logging_consent'] == true,
      consentRevokedAt: DateTime.tryParse(
        '${json['consent_revoked_at'] ?? ''}',
      ),
      privacyPolicyVersion: '${json['privacy_policy_version'] ?? '2026.05'}',
    );
  }

  bool get notificationConsent => auditLoggingConsent;
}

class ConsentApi {
  final ApiClient _apiClient;

  const ConsentApi({required ApiClient apiClient}) : _apiClient = apiClient;

  Future<ConsentState> getConsent() async {
    final response = await _apiClient.get('/api/v1/consent');
    return ConsentState.fromJson(_map(response));
  }

  Future<ConsentState> updateConsent(Map<String, dynamic> changes) async {
    final response = await _apiClient.patch(
      '/api/v1/consent',
      body: _toBackendChanges(changes),
    );
    return ConsentState.fromJson(_map(response));
  }

  Map<String, dynamic> _toBackendChanges(Map<String, dynamic> changes) {
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

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    throw const ApiException(message: '동의 설정 응답을 확인하지 못했어요.');
  }
}
