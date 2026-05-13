import 'package:flutter_test/flutter_test.dart';
import 'package:little_signals/features/cycles/models/cycle.dart';
import 'package:little_signals/features/cycles/services/cycle_phase_resolver.dart';

void main() {
  test('uses local inclusive day count instead of backend UTC phase/day', () {
    final today = DateTime.now();
    final periodStart = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: 13));
    final cycle = Cycle(
      id: 'cycle-current',
      lastPeriodStart: periodStart,
      periodEndDate: periodStart.add(const Duration(days: 11)),
      cycleLength: 28,
      periodLength: 12,
      notes: null,
      backendPhase: 'follicular',
      backendDay: 13,
    );
    final resolved = CyclePhaseResolver.resolve(
      periodStart: cycle.lastPeriodStart,
      targetDate: today,
      cycleLength: cycle.cycleLength,
      periodLength: cycle.periodLength,
    );

    expect(resolved.day, 14);
    expect(resolved.phase, 'ovulation');
    expect(cycle.cycleDay, resolved.day);
    expect(cycle.phase, resolved.phase);
  });

  test('keeps day and phase stable when period end is null', () {
    final periodStart = DateTime(2026, 4, 30);
    final targetDate = DateTime(2026, 5, 13);
    final resolved = CyclePhaseResolver.resolve(
      periodStart: periodStart,
      targetDate: targetDate,
      cycleLength: 28,
      periodLength: 7,
    );

    expect(resolved.day, 14);
    expect(resolved.phase, 'ovulation');
  });
}
