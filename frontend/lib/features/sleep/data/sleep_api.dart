import '../../../core/errors/api_exception.dart';
import '../../../core/network/api_client.dart';
import '../models/sleep_log.dart';

class SleepApi {
  final ApiClient _apiClient;

  const SleepApi({required ApiClient apiClient}) : _apiClient = apiClient;

  Future<SleepLog> createSleepLog(SleepLog sleepLog) async {
    final response = await _apiClient.post(
      '/api/v1/sleep-logs',
      body: sleepLog.toCreateJson(),
    );
    return SleepLog.fromJson(_map(response));
  }

  Future<SleepLog?> getLatestSleepLog() async {
    try {
      final response = await _apiClient.get('/api/v1/sleep-logs/latest');
      if (response == null) return null;
      final sleepLogMap = _nullableSleepLogMap(response);
      if (sleepLogMap == null) return null;
      return SleepLog.fromJson(sleepLogMap);
    } on ApiException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<List<SleepLog>> listSleepLogs({
    DateTime? start,
    DateTime? end,
    int limit = 200,
  }) async {
    final queryParameters = <String, String>{'limit': limit.toString()};
    if (start != null) {
      queryParameters['start'] = _apiRangeStart(start);
    }
    if (end != null) {
      queryParameters['end'] = _apiRangeEnd(end);
    }

    final response = await _apiClient.get(
      '/api/v1/sleep-logs',
      queryParameters: queryParameters,
    );
    if (response == null) return const [];
    return _list(response).map(SleepLog.fromJson).toList();
  }

  Future<SleepLog> getSleepLog(String id) async {
    final response = await _apiClient.get('/api/v1/sleep-logs/$id');
    return SleepLog.fromJson(_map(response));
  }

  Future<SleepLog> updateSleepLog(SleepLog sleepLog) async {
    final response = await _apiClient.patch(
      '/api/v1/sleep-logs/${sleepLog.id}',
      body: sleepLog.toUpdateJson(),
    );
    return SleepLog.fromJson(_map(response));
  }

  Future<void> deleteSleepLog(String id) async {
    await _apiClient.delete('/api/v1/sleep-logs/$id');
  }

  List<Map<String, dynamic>> _list(dynamic value) {
    final list = value is Map<String, dynamic>
        ? value['items'] ?? value['sleep_logs'] ?? value['logs']
        : value;
    if (list is List) {
      return list.whereType<Map<String, dynamic>>().toList();
    }
    throw const ApiException(message: '수면 기록 응답을 확인하지 못했어요.');
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    throw const ApiException(message: '수면 기록 응답을 확인하지 못했어요.');
  }

  Map<String, dynamic>? _nullableSleepLogMap(dynamic value) {
    if (value is! Map<String, dynamic>) {
      throw const ApiException(message: '수면 기록 응답을 확인하지 못했어요.');
    }

    final source = value['sleep_log'] is Map<String, dynamic>
        ? value['sleep_log'] as Map<String, dynamic>
        : value;
    final fellAsleepAt = source['fell_asleep_at'];
    final wokeUpAt = source['woke_up_at'];

    if (fellAsleepAt == null ||
        '$fellAsleepAt'.trim().isEmpty ||
        wokeUpAt == null ||
        '$wokeUpAt'.trim().isEmpty) {
      return null;
    }

    return source;
  }

  String _apiRangeStart(DateTime date) {
    return DateTime(date.year, date.month, date.day).toUtc().toIso8601String();
  }

  String _apiRangeEnd(DateTime date) {
    return DateTime(
      date.year,
      date.month,
      date.day,
      23,
      59,
      59,
      999,
    ).toUtc().toIso8601String();
  }
}
