import 'package:flutter_test/flutter_test.dart';
import 'package:little_signals/features/cycles/services/cycle_insight_service.dart';
import 'package:little_signals/features/events/models/stress_event.dart';

void main() {
  test('returns fallback when stress records are limited', () {
    final service = CycleInsightService();

    expect(
      service.buildStressInsight(
        events: [
          _event(
            id: 'event-1',
            phase: 'luteal',
            score: 72,
            day: DateTime(2026, 5, 8),
          ),
        ],
        cycles: const [],
        currentPhase: 'luteal',
      ),
      '기록이 조금 더 쌓이면 사이클별 스트레스 패턴을 알려드릴게요.',
    );
  });

  test('summarizes stress concentration by cycle phase', () {
    final service = CycleInsightService();
    final events = [
      _event(
        id: 'event-1',
        phase: 'luteal',
        score: 72,
        day: DateTime(2026, 5, 8),
      ),
      _event(
        id: 'event-2',
        phase: 'luteal',
        score: 68,
        day: DateTime(2026, 5, 7),
      ),
      _event(
        id: 'event-3',
        phase: 'luteal',
        score: 74,
        day: DateTime(2026, 5, 6),
      ),
      _event(
        id: 'event-4',
        phase: 'luteal',
        score: 63,
        day: DateTime(2026, 5, 5),
      ),
      _event(
        id: 'event-5',
        phase: 'menstrual',
        score: 61,
        day: DateTime(2026, 5, 4),
      ),
      _event(
        id: 'event-6',
        phase: 'follicular',
        score: 47,
        day: DateTime(2026, 5, 3),
      ),
    ];

    expect(
      service.buildStressInsight(
        events: events,
        cycles: const [],
        currentPhase: 'luteal',
      ),
      '최근 스트레스 기록의 67%가 황체기에 집중되어 있어요.',
    );
  });
}

StressEvent _event({
  required String id,
  required String phase,
  required int score,
  required DateTime day,
}) {
  return StressEvent(
    id: id,
    detectedAt: day,
    cyclePhase: phase,
    stressScore: score,
    trigger: 'Work',
    note: null,
  );
}
