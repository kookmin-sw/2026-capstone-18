import '../../../core/errors/api_exception.dart';
import '../../../core/network/api_client.dart';
import 'morning_tip.dart';
import 'pattern_tip.dart';
import 'range_report.dart';

class AiInsightsApi {
  final ApiClient _apiClient;

  const AiInsightsApi({required ApiClient apiClient}) : _apiClient = apiClient;

  /// Fetch today's contextual morning tip composed by the backend agent
  /// from current cycle phase, last night's sleep, and recent patterns.
  /// Returns null when the backend has nothing to surface (404).
  Future<MorningTip?> getMorningTip() async {
    try {
      final response = await _apiClient.get('/api/v1/insights/morning-tip');
      if (response is! Map<String, dynamic>) return null;
      return MorningTip.fromJson(response);
    } on ApiException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<RangeReport?> getRangeReport({
    required DateTime frm,
    required DateTime to,
  }) async {
    final f = _fmtDate(frm);
    final t = _fmtDate(to);
    try {
      final response = await _apiClient.get(
        '/api/v1/reports/range?frm=$f&to=$t',
      );
      if (response is! Map<String, dynamic>) return null;
      return RangeReport.fromJson(response);
    } on ApiException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  static String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

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
