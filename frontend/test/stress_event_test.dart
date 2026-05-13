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

  test('includes category id in create body when present', () {
    final body = StressEvent(
      id: '',
      detectedAt: DateTime.utc(2026, 5, 8, 12),
      stressScore: 50,
      trigger: 'Family',
      note: null,
      logChips: const ['Family'],
      categoryId: 'category-family',
    ).toCreateJson();

    expect(body['category_id'], 'category-family');
    expect(body['log_chips'], ['Family']);
  });

  test('parses category id from backend response', () {
    final event = StressEvent.fromJson({
      'id': 'event-1',
      'detected_at': '2026-05-08T12:00:00Z',
      'logged': true,
      'user_stress_level': 64,
      'log_chips': ['Work'],
      'category_id': 'category-work',
    });

    expect(event.categoryId, 'category-work');
    expect(event.trigger, 'Work');
  });
}
