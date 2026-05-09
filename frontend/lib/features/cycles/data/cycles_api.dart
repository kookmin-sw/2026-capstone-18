import '../../../core/errors/api_exception.dart';
import '../../../core/network/api_client.dart';
import '../models/cycle.dart';

class CyclesApi {
  final ApiClient _apiClient;

  const CyclesApi({required ApiClient apiClient}) : _apiClient = apiClient;

  Future<Cycle> createPeriod(Cycle cycle) async {
    final createdResponse = await _apiClient.post(
      '/api/v1/cycles/period-start',
      body: cycle.toCreateJson(),
    );
    final created = Cycle.fromJson(_map(createdResponse));

    if (cycle.periodEndDate == null || created.id.isEmpty) {
      return created;
    }

    return updateCycle(created.id, {
      'period_end_date': _date(cycle.periodEndDate!),
    });
  }

  Future<List<Cycle>> listCycles() async {
    final response = await _apiClient.get('/api/v1/cycles/history');
    return _list(response).map(Cycle.fromJson).toList();
  }

  Future<Cycle?> currentCycle() async {
    try {
      final response = await _apiClient.get('/api/v1/cycles/current');
      if (response == null) return null;

      final cycleMap = _nullableCycleMap(response);
      if (cycleMap == null) return null;

      return Cycle.fromJson(cycleMap);
    } on ApiException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<Cycle> updateCycle(String id, Map<String, dynamic> changes) async {
    final response = await _apiClient.patch(
      '/api/v1/cycles/$id',
      body: changes,
    );
    return Cycle.fromJson(_map(response));
  }

  Future<void> importCycles(List<Cycle> cycles) async {
    for (final cycle in cycles) {
      await createPeriod(cycle);
    }
  }

  List<Map<String, dynamic>> _list(dynamic value) {
    final list = value is Map<String, dynamic> ? value['items'] : value;
    if (list is List) {
      return list.whereType<Map<String, dynamic>>().toList();
    }
    throw const ApiException(message: '생리 주기 기록 응답을 확인하지 못했어요.');
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    throw const ApiException(message: '생리 주기 기록 응답을 확인하지 못했어요.');
  }

  Map<String, dynamic>? _nullableCycleMap(dynamic value) {
    if (value is! Map<String, dynamic>) {
      throw const ApiException(message: '생리 주기 기록 응답을 확인하지 못했어요.');
    }

    final source = value['cycle'] is Map<String, dynamic>
        ? value['cycle'] as Map<String, dynamic>
        : value;

    final periodStart =
        source['period_start_date'] ?? source['last_period_start'];

    if (periodStart == null || '$periodStart'.trim().isEmpty) {
      return null;
    }

    return source;
  }

  String _date(DateTime date) {
    final dateOnly = DateTime(date.year, date.month, date.day);
    return dateOnly.toIso8601String().split('T').first;
  }
}
