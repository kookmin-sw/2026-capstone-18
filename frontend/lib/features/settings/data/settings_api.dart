import '../../../core/errors/api_exception.dart';
import '../../../core/network/api_client.dart';

class UserSettings {
  final int notificationMaxPerDay;
  final double stressThreshold;
  final String quietHoursStart;
  final String quietHoursEnd;
  final bool silenceDuringMeeting;
  final bool silenceDuringExercise;
  final bool consentAuditLogging;
  final bool sleepNudgeEnabled;
  final String language;

  const UserSettings({
    required this.notificationMaxPerDay,
    required this.stressThreshold,
    required this.quietHoursStart,
    required this.quietHoursEnd,
    required this.silenceDuringMeeting,
    required this.silenceDuringExercise,
    required this.consentAuditLogging,
    required this.sleepNudgeEnabled,
    required this.language,
  });

  factory UserSettings.fromJson(Map<String, dynamic> json) {
    return UserSettings(
      notificationMaxPerDay:
          (json['notification_max_per_day'] as num?)?.round() ?? 5,
      stressThreshold: (json['stress_threshold'] as num?)?.toDouble() ?? 0.75,
      quietHoursStart: '${json['quiet_hours_start'] ?? '22:00:00'}',
      quietHoursEnd: '${json['quiet_hours_end'] ?? '08:00:00'}',
      silenceDuringMeeting: json['silence_during_meeting'] == true,
      silenceDuringExercise: json['silence_during_exercise'] == true,
      consentAuditLogging: json['consent_audit_logging'] != false,
      sleepNudgeEnabled:
          json['sleep_nudge_enabled'] == true ||
          json['notification_consent'] == true ||
          json['notifications_enabled'] == true,
      language: '${json['language'] ?? 'ko'}',
    );
  }

  bool get notificationsEnabled => sleepNudgeEnabled;
  int get dataRetentionDays => 365;
  String? get watchStatus => null;

  Map<String, dynamic> toJson() {
    return {
      'notification_max_per_day': notificationMaxPerDay,
      'stress_threshold': stressThreshold,
      'quiet_hours_start': quietHoursStart,
      'quiet_hours_end': quietHoursEnd,
      'silence_during_meeting': silenceDuringMeeting,
      'silence_during_exercise': silenceDuringExercise,
      'consent_audit_logging': consentAuditLogging,
      'sleep_nudge_enabled': sleepNudgeEnabled,
      'language': language,
    };
  }
}

class SettingsApi {
  final ApiClient _apiClient;

  const SettingsApi({required ApiClient apiClient}) : _apiClient = apiClient;

  Future<UserSettings> getSettings() async {
    final response = await _apiClient.get('/api/v1/settings');
    return UserSettings.fromJson(_map(response));
  }

  Future<UserSettings> updateSettings(Map<String, dynamic> changes) async {
    final body = _toBackendChanges(changes);
    if (body.isEmpty) {
      throw const ApiException(message: '이 설정은 곧 사용할 수 있어요.');
    }

    final response = await _apiClient.patch('/api/v1/settings', body: body);
    return UserSettings.fromJson(_map(response));
  }

  Map<String, dynamic> _toBackendChanges(Map<String, dynamic> changes) {
    final body = <String, dynamic>{};

    void copy(String key) {
      if (changes.containsKey(key)) body[key] = changes[key];
    }

    copy('notification_max_per_day');
    copy('stress_threshold');
    copy('quiet_hours_start');
    copy('quiet_hours_end');
    copy('silence_during_meeting');
    copy('silence_during_exercise');
    copy('consent_audit_logging');
    copy('sleep_nudge_enabled');
    copy('language');

    if (changes.containsKey('notification_consent')) {
      body['sleep_nudge_enabled'] = changes['notification_consent'];
    }
    if (changes.containsKey('notifications_enabled')) {
      body['sleep_nudge_enabled'] = changes['notifications_enabled'];
    }

    return body;
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    throw const ApiException(message: '설정 응답을 확인하지 못했어요.');
  }
}
