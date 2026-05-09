import '../../../core/network/api_client.dart';

class BiosignalSyncService {
  final ApiClient _apiClient;

  const BiosignalSyncService({required ApiClient apiClient})
    : _apiClient = apiClient;

  Future<void> uploadEncryptedBiosignals({
    required Map<String, dynamic> encryptedPayload,
  }) async {
    await _apiClient.post('/api/v1/sync/biosignals', body: encryptedPayload);
  }
}
