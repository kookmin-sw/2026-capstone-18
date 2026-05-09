import 'package:flutter_test/flutter_test.dart';
import 'package:little_signals/features/events/models/stress_event.dart';

void main() {
  test('omits invalid cycle context from create body', () {
    final body = StressEvent(
      id: '',
      detectedAt: DateTime.utc(2026, 5, 8, 12),
      stressScore: 50,
      trigger: '',
      note: null,
      cyclePhase: 'unknown',
      cycleDay: 0,
    ).toCreateJson();

    expect(body, isNot(contains('cycle_phase')));
    expect(body, isNot(contains('cycle_day')));
  });

  test('normalizes valid cycle context for create body', () {
    final body = StressEvent(
      id: '',
      detectedAt: DateTime.utc(2026, 5, 8, 12),
      stressScore: 50,
      trigger: '',
      note: null,
      cyclePhase: 'Luteal phase',
      cycleDay: 22,
    ).toCreateJson();

    expect(body['cycle_phase'], 'luteal');
    expect(body['cycle_day'], 22);
  });
}
