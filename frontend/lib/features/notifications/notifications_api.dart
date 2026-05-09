import '../../core/network/api_client.dart';

class NotificationsApi {
  final ApiClient _apiClient;

  const NotificationsApi({required ApiClient apiClient})
    : _apiClient = apiClient;

  Future<void> registerDeviceToken(String token) async {
    await _apiClient.post(
      '/api/v1/devices/fcm-token',
      body: {'token': token, 'platform': 'android'},
    );
  }

  Future<void> unregisterDeviceToken(String token) async {
  }
}
