import 'package:flutter_test/flutter_test.dart';
import 'package:little_signals/features/cycles/models/cycle.dart';
import 'package:little_signals/features/insight/services/insight_calendar_phase_resolver.dart';

void main() {
  test('keeps default month-day coloring when no cycle data exists', () {
    expect(
      InsightCalendarPhaseResolver.phaseForDate(
        date: DateTime(2026, 5, 3),
        cycles: const [],
      ),
      'menstrual',
    );
    expect(
      InsightCalendarPhaseResolver.phaseForDate(
        date: DateTime(2026, 5, 14),
        cycles: const [],
      ),
      'ovulation',
    );
  });

  test('uses recorded cycle dates for calendar phase coloring', () {
    final cycle = _cycle(
      start: DateTime(2026, 5, 4),
      end: DateTime(2026, 5, 11),
    );

    expect(
      InsightCalendarPhaseResolver.phaseForDate(
        date: DateTime(2026, 5, 3),
        cycles: [cycle],
      ),
      isNull,
    );
    expect(
      InsightCalendarPhaseResolver.phaseForDate(
        date: DateTime(2026, 5, 4),
        cycles: [cycle],
      ),
      'menstrual',
    );
    expect(
      InsightCalendarPhaseResolver.phaseForDate(
        date: DateTime(2026, 5, 11),
        cycles: [cycle],
      ),
      'menstrual',
    );
    expect(
      InsightCalendarPhaseResolver.phaseForDate(
        date: DateTime(2026, 5, 12),
        cycles: [cycle],
      ),
      'follicular',
    );
  });

  test('ongoing period keeps dates from start through today menstrual', () {
    final cycle = _cycle(
      start: DateTime(2026, 5),
      end: null,
      periodOngoing: true,
    );

    expect(
      InsightCalendarPhaseResolver.phaseForDate(
        date: DateTime(2026, 5, 13),
        cycles: [cycle],
        today: DateTime(2026, 5, 13),
      ),
      'menstrual',
    );
  });
}

Cycle _cycle({
  required DateTime start,
  required DateTime? end,
  bool periodOngoing = false,
}) {
  return Cycle(
    id: 'cycle-${start.toIso8601String()}',
    lastPeriodStart: start,
    periodEndDate: end,
    cycleLength: 28,
    periodLength: end == null ? 7 : end.difference(start).inDays + 1,
    notes: null,
    periodOngoing: periodOngoing,
  );
}
