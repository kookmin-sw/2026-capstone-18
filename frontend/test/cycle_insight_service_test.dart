import 'package:flutter_test/flutter_test.dart';
import 'package:little_signals/features/cycles/services/cycle_insight_service.dart';
import 'package:little_signals/features/events/models/stress_event.dart';

void main() {
  test('returns cycle guide when cycle data is missing', () {
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
      '주기 정보를 입력하면 스트레스와 주기의 관계를 더 정확히 볼 수 있어요.',
    );
  });

  test('does not summarize phase concentration without cycle data', () {
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
      '주기 정보를 입력하면 스트레스와 주기의 관계를 더 정확히 볼 수 있어요.',
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
