import '../../../core/utils/korean_ui_text.dart';
import '../../events/models/stress_event.dart';
import '../../insight/services/insight_analytics_service.dart';
import '../models/cycle.dart';

class CycleInsightService {
  final InsightAnalyticsService _analyticsService;

  CycleInsightService({InsightAnalyticsService? analyticsService})
    : _analyticsService = analyticsService ?? InsightAnalyticsService();

  String buildStressInsight({
    required List<StressEvent> events,
    required List<Cycle> cycles,
    required String currentPhase,
  }) {
    final loggedEvents = events
        .where((event) => event.isLoggedWithScore)
        .toList();
    if (loggedEvents.length < 6) {
      return '기록이 조금 더 쌓이면 사이클별 스트레스 패턴을 알려드릴게요.';
    }

    final countsByPhase = {
      for (final phase in InsightAnalyticsService.phases) phase: 0,
    };

    for (final event in loggedEvents) {
      final phase = _analyticsService.phaseForEvent(event, cycles);
      countsByPhase[phase] = (countsByPhase[phase] ?? 0) + 1;
    }

    final strongestPhase = countsByPhase.entries.reduce(
      (best, current) => current.value > best.value ? current : best,
    );
    final concentration = strongestPhase.value / loggedEvents.length;
    if (strongestPhase.value >= 3 && concentration >= 0.45) {
      final percent = (concentration * 100).round();
      return '최근 스트레스 기록의 $percent%가 ${koPhase(strongestPhase.key)}에 집중되어 있어요.';
    }

    final normalizedCurrentPhase = InsightAnalyticsService.normalizePhase(
      currentPhase,
    );
    final currentCount = countsByPhase[normalizedCurrentPhase] ?? 0;
    final otherCounts = countsByPhase.entries
        .where((entry) => entry.key != normalizedCurrentPhase)
        .map((entry) => entry.value)
        .toList();
    final otherAverage = otherCounts.isEmpty
        ? 0
        : otherCounts.reduce((a, b) => a + b) / otherCounts.length;

    if (currentCount >= 2 && currentCount >= otherAverage + 2) {
      return '현재 ${koPhase(normalizedCurrentPhase)}에서 스트레스 기록이 평소보다 조금 많아요.';
    }

    final lutealAverage = _averageStressForPhase(
      loggedEvents,
      cycles,
      'luteal',
    );
    final beforeLutealAverage = _averageStressExcludingPhase(
      loggedEvents,
      cycles,
      'luteal',
    );
    if (lutealAverage != null &&
        beforeLutealAverage != null &&
        lutealAverage >= beforeLutealAverage + 10) {
      return '배란기 이후 스트레스 반응이 조금 증가하는 패턴이 보여요.';
    }

    return '사이클 전반의 스트레스 기록이 비교적 고르게 분포해 있어요.';
  }

  double? _averageStressForPhase(
    List<StressEvent> events,
    List<Cycle> cycles,
    String phase,
  ) {
    final scores = events
        .where(
          (event) => _analyticsService.phaseForEvent(event, cycles) == phase,
        )
        .map((event) => event.stressScore)
        .whereType<int>()
        .toList();
    if (scores.length < 2) return null;
    return scores.reduce((a, b) => a + b) / scores.length;
  }

  double? _averageStressExcludingPhase(
    List<StressEvent> events,
    List<Cycle> cycles,
    String phase,
  ) {
    final scores = events
        .where(
          (event) => _analyticsService.phaseForEvent(event, cycles) != phase,
        )
        .map((event) => event.stressScore)
        .whereType<int>()
        .toList();
    if (scores.length < 2) return null;
    return scores.reduce((a, b) => a + b) / scores.length;
  }
}
