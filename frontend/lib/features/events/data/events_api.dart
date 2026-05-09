import '../../../core/errors/api_exception.dart';
import '../../../core/network/api_client.dart';
import '../models/stress_event.dart';

class EventsApi {
  final ApiClient _apiClient;
  static const _legacyBackendUserResponse = 'breathe';

  const EventsApi({required ApiClient apiClient}) : _apiClient = apiClient;

  Future<List<StressEvent>> listEvents({
    DateTime? start,
    DateTime? end,
    bool? logged,
    String? cyclePhase,
    String? chip,
    String? cursor,
    int limit = 50,
  }) async {
    final queryParameters = <String, String>{'limit': limit.toString()};
    if (start != null) {
      queryParameters['start'] = start.toUtc().toIso8601String();
    }
    if (end != null) {
      queryParameters['end'] = end.toUtc().toIso8601String();
    }
    if (logged != null) {
      queryParameters['logged'] = logged.toString();
    }
    if (cyclePhase != null) {
      queryParameters['cycle_phase'] = cyclePhase;
    }
    if (chip != null) {
      queryParameters['chip'] = chip;
    }
    if (cursor != null) {
      queryParameters['cursor'] = cursor;
    }

    final response = await _apiClient.get(
      '/api/v1/events',
      queryParameters: queryParameters,
    );

    return _list(response).map(StressEvent.fromJson).toList();
  }

  Future<StressEvent> getEvent(String id) async {
    final response = await _apiClient.get('/api/v1/events/$id');
    return StressEvent.fromJson(_map(response));
  }

  Future<StressEvent> createEvent(StressEvent event) async {
    final body = _withBackendCompatibility(event.toCreateJson());

    final response = await _apiClient.post('/api/v1/events', body: body);
    return StressEvent.fromJson(_map(response));
  }

  Future<StressEvent> updateEvent(
    String id,
    Map<String, dynamic> changes,
  ) async {
    final response = await _apiClient.patch(
      '/api/v1/events/$id',
      body: _withBackendCompatibility(changes),
    );
    return StressEvent.fromJson(_map(response));
  }

  Future<void> deleteEvent(String id) async {
    await _apiClient.delete('/api/v1/events/$id');
  }

  List<Map<String, dynamic>> _list(dynamic value) {
    final list = value is Map<String, dynamic> ? value['items'] : value;
    if (list is List) {
      return list.whereType<Map<String, dynamic>>().toList();
    }
    throw const ApiException(message: '스트레스 기록 응답을 확인하지 못했어요.');
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    throw const ApiException(message: '스트레스 기록 응답을 확인하지 못했어요.');
  }

  Map<String, dynamic> _withBackendCompatibility(Map<String, dynamic> body) {
    // Legacy backend contract: event writes still require this field.
    return {...body, 'user_response': _legacyBackendUserResponse};
  }
}
