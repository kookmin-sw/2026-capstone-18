import '../../../core/errors/api_exception.dart';
import '../../../core/network/api_client.dart';
import 'pattern_tip.dart';
import 'weekly_report.dart';

class AiInsightsApi {
  final ApiClient _apiClient;

  const AiInsightsApi({required ApiClient apiClient}) : _apiClient = apiClient;

  /// Fetch the latest AI-generated weekly report. Returns null if none exists
  /// or the AI features flag is off (backend returns 404 in both cases).
  Future<WeeklyReport?> getLatestWeeklyReport() async {
    try {
      final response = await _apiClient.get('/api/v1/reports/weekly');
      if (response is! Map<String, dynamic>) return null;
      return WeeklyReport.fromJson(response);
    } on ApiException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Reserved for future use — fetch a tip for a specific pattern key.
  /// Not yet wired into UI; the local insights pipeline doesn't expose
  /// backend pattern keys. Backend route exists at GET /api/v1/insights/tips/{key}.
  Future<PatternTip?> getPatternTip(String patternKey) async {
    try {
      final response = await _apiClient.get(
        '/api/v1/insights/tips/$patternKey',
      );
      if (response is! Map<String, dynamic>) return null;
      return PatternTip.fromJson(response);
    } on ApiException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }
}
