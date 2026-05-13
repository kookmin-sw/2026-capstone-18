import 'package:flutter_test/flutter_test.dart';
import 'package:little_signals/features/cycles/models/cycle.dart';
import 'package:little_signals/features/events/models/stress_event.dart';
import 'package:little_signals/features/insight/services/insight_analytics_service.dart';

void main() {
  final service = InsightAnalyticsService();
  final cycles = [
    Cycle(
      id: 'cycle-may',
      lastPeriodStart: DateTime(2026, 5),
      periodEndDate: DateTime(2026, 5, 5),
      cycleLength: 28,
      periodLength: 5,
      notes: null,
    ),
    Cycle(
      id: 'cycle-june',
      lastPeriodStart: DateTime(2026, 6),
      periodEndDate: DateTime(2026, 6, 5),
      cycleLength: 28,
      periodLength: 5,
      notes: null,
    ),
  ];

  final events = [
    _event(id: 'men-low', day: DateTime(2026, 5, 1), score: 20),
    _event(id: 'men-zero', day: DateTime(2026, 5, 2), score: 0),
    _event(id: 'foll', day: DateTime(2026, 5, 6), score: 40),
    _event(id: 'ovul', day: DateTime(2026, 5, 14), score: 80),
    _event(id: 'lut-low', day: DateTime(2026, 5, 20), score: 60),
    _event(id: 'lut-high', day: DateTime(2026, 5, 21), score: 100),
    _event(id: 'null-score', day: DateTime(2026, 5, 22), score: null),
    _event(
      id: 'unlogged',
      day: DateTime(2026, 5, 23),
      score: 90,
      logged: false,
    ),
    _event(id: 'june-foll', day: DateTime(2026, 6, 6), score: 90),
  ];

  test(
    'phase distribution counts and phase averages use the same range data',
    () {
      final report = service.buildReport(
        events: events,
        cycles: cycles,
        range: _rangeForMonth(2026, 5),
      );

      expect(report.totalEvents, 6);
      expect(report.averageStress, 50);

      for (final phaseAverage in report.phaseAverages) {
        final distributionItem = report.phaseDistribution.items.firstWhere(
          (item) => item.phase == phaseAverage.phase,
        );
        expect(distributionItem.phaseLogCount, phaseAverage.count);
      }

      expect(_phase(report, 'menstrual').count, 2);
      expect(_phase(report, 'menstrual').averageStress, 10);
      expect(
        report.phaseDistribution.items
            .firstWhere((item) => item.phase == 'menstrual')
            .phaseDistributionRatio,
        closeTo(33.33, 0.01),
      );
    },
  );

  test('changing selected month updates phase averages', () {
    final mayReport = service.buildReport(
      events: events,
      cycles: cycles,
      range: _rangeForMonth(2026, 5),
    );
    final juneReport = service.buildReport(
      events: events,
      cycles: cycles,
      range: _rangeForMonth(2026, 6),
    );

    expect(_phase(mayReport, 'follicular').averageStress, 40);
    expect(_phase(juneReport, 'follicular').averageStress, 90);
    expect(mayReport.totalEvents, 6);
    expect(juneReport.totalEvents, 1);
  });

  test('deleted event list is excluded from phase averages', () {
    final afterDelete = events
        .where((event) => event.id != 'lut-high')
        .toList();
    final report = service.buildReport(
      events: afterDelete,
      cycles: cycles,
      range: _rangeForMonth(2026, 5),
    );

    expect(_phase(report, 'luteal').count, 1);
    expect(_phase(report, 'luteal').averageStress, 60);
  });

  test('today event participates through the current ongoing cycle', () {
    final today = DateTime.now();
    final currentCycle = Cycle(
      id: 'current-cycle',
      lastPeriodStart: DateTime(
        today.year,
        today.month,
        today.day,
      ).subtract(const Duration(days: 13)),
      periodEndDate: null,
      cycleLength: 28,
      periodLength: 5,
      notes: null,
    );
    final todayEvent = _event(
      id: 'today-event',
      day: today,
      score: 77,
      phase: 'unknown',
    );
    final report = service.buildReport(
      events: [todayEvent],
      cycles: [currentCycle],
      range: InsightDateRange(
        start: DateTime(today.year, today.month),
        endExclusive: DateTime(today.year, today.month + 1),
        monthCount: 1,
      ),
    );

    expect(_phase(report, 'ovulation').count, 1);
    expect(_phase(report, 'ovulation').averageStress, 77);
    expect(report.phaseDistribution.highestDistributionPhase, 'ovulation');
  });

  test(
    'current ongoing cycle classifies current period events as menstrual',
    () {
      final today = DateTime.now();
      final currentCycle = Cycle(
        id: 'current-ongoing-cycle',
        lastPeriodStart: DateTime(
          today.year,
          today.month,
          today.day,
        ).subtract(const Duration(days: 13)),
        periodEndDate: null,
        cycleLength: 28,
        periodLength: 5,
        notes: null,
        periodOngoing: true,
      );
      final todayEvent = _event(
        id: 'ongoing-today-event',
        day: today,
        score: 77,
        phase: 'unknown',
      );
      final report = service.buildReport(
        events: [todayEvent],
        cycles: [currentCycle],
        range: InsightDateRange(
          start: DateTime(today.year, today.month),
          endExclusive: DateTime(today.year, today.month + 1),
          monthCount: 1,
        ),
      );

      expect(_phase(report, 'menstrual').count, 1);
      expect(_phase(report, 'menstrual').averageStress, 77);
      expect(report.phaseDistribution.highestDistributionPhase, 'menstrual');
      expect(service.phaseForDate(today, [currentCycle]), 'menstrual');
    },
  );

  test('events without cycle data stay out of phase aggregation', () {
    final noCycleEvent = _event(
      id: 'no-cycle-event',
      day: DateTime(2026, 5, 13),
      score: 55,
      phase: 'luteal',
    );
    final report = service.buildReport(
      events: [noCycleEvent],
      cycles: const [],
      range: _rangeForMonth(2026, 5),
    );

    expect(report.totalEvents, 1);
    expect(report.averageStress, 55);
    expect(report.triggerRanking.single.count, 1);
    expect(report.phaseDistribution.totalLogs, 0);
    expect(report.hasPhaseData, isFalse);
    expect(report.peakStressPhase, isNull);
    for (final phaseAverage in report.phaseAverages) {
      expect(phaseAverage.count, 0);
      expect(phaseAverage.averageStress, 0);
    }
    expect(service.phaseForEvent(noCycleEvent, const []), 'unknown');
    expect(service.cycleDayForEvent(noCycleEvent, const []), isNull);
  });
}

InsightDateRange _rangeForMonth(int year, int month) {
  return InsightDateRange(
    start: DateTime(year, month),
    endExclusive: DateTime(year, month + 1),
    monthCount: 1,
  );
}

PhaseAverage _phase(InsightReportViewModel report, String phase) {
  return report.phaseAverages.firstWhere((item) => item.phase == phase);
}

StressEvent _event({
  required String id,
  required DateTime day,
  required int? score,
  String phase = 'unknown',
  bool logged = true,
}) {
  return StressEvent(
    id: id,
    detectedAt: day,
    cyclePhase: phase,
    stressScore: score,
    logged: logged,
    trigger: 'Work',
    note: null,
  );
}
