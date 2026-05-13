import '../../../core/utils/cycle_phase_ui.dart';
import '../../cycles/models/cycle.dart';
import '../../events/models/stress_event.dart';

class InsightDateRange {
  final DateTime start;
  final DateTime endExclusive;
  final int monthCount;

  const InsightDateRange({
    required this.start,
    required this.endExclusive,
    required this.monthCount,
  });

  bool contains(DateTime date) =>
      !date.isBefore(start) && date.isBefore(endExclusive);

  String get label {
    final endMonth = DateTime(endExclusive.year, endExclusive.month - 1);
    if (start.year == endMonth.year && start.month == endMonth.month) {
      return '${start.year}년 ${start.month}월';
    }
    if (start.year == endMonth.year) {
      return '${start.year}년 ${start.month}월-${endMonth.month}월';
    }
    return '${start.year}년 ${start.month}월-${endMonth.year}년 ${endMonth.month}월';
  }

  String get compactLabel {
    final endMonth = DateTime(endExclusive.year, endExclusive.month - 1);
    if (start.year == endMonth.year && start.month == endMonth.month) {
      return '${start.year}년 ${start.month}월';
    }
    return '${start.month}월-${endMonth.month}월';
  }
}

class PhaseAverage {
  final String phase;
  final int count;
  final double averageStress;

  const PhaseAverage({
    required this.phase,
    required this.count,
    required this.averageStress,
  });

  String get label => InsightAnalyticsService.phaseLabel(phase);
  String get shortLabel => InsightAnalyticsService.phaseShortLabel(phase);
  double get value => (averageStress / 100).clamp(0.0, 1.0);
  String get percent => '${averageStress.round()}%';
}

class PhaseDistributionItem {
  final String phase;
  final int phaseLogCount;
  final double phaseDistributionRatio;

  const PhaseDistributionItem({
    required this.phase,
    required this.phaseLogCount,
    required this.phaseDistributionRatio,
  });
}

class PhaseDistribution {
  final List<PhaseDistributionItem> items;
  final int totalLogs;

  const PhaseDistribution({required this.items, required this.totalLogs});

  PhaseDistributionItem get highestDistributionItem {
    return items.reduce((best, current) {
      if (current.phaseLogCount > best.phaseLogCount) return current;
      if (current.phaseLogCount == best.phaseLogCount &&
          current.phaseDistributionRatio > best.phaseDistributionRatio) {
        return current;
      }
      return best;
    });
  }

  String get highestDistributionPhase => highestDistributionItem.phase;

  double get highestDistributionRatio =>
      highestDistributionItem.phaseDistributionRatio;
}

class MonthlyStressByPhase {
  final DateTime month;
  final Map<String, double> averageByPhase;
  final Map<String, int> countByPhase;

  const MonthlyStressByPhase({
    required this.month,
    required this.averageByPhase,
    required this.countByPhase,
  });

  String get label {
    return '${month.month}월';
  }
}

class TriggerPhaseCell {
  final String trigger;
  final String phase;
  final int count;
  final double averageStress;

  const TriggerPhaseCell({
    required this.trigger,
    required this.phase,
    required this.count,
    required this.averageStress,
  });
}

class TriggerRankingItem {
  final String trigger;
  final int count;
  final double averageStress;

  const TriggerRankingItem({
    required this.trigger,
    required this.count,
    required this.averageStress,
  });
}

class InsightReportViewModel {
  final InsightDateRange range;
  final List<StressEvent> events;
  final List<PhaseAverage> phaseAverages;
  final PhaseDistribution phaseDistribution;
  final List<MonthlyStressByPhase> monthlyStressByPhase;
  final List<String> triggers;
  final List<TriggerPhaseCell> triggerByCyclePhaseMatrix;
  final List<TriggerRankingItem> triggerRanking;
  final int totalEvents;
  final double averageStress;
  final int? mostCommonCycleDay;
  final String? peakStressPhase;
  final List<StressEvent> recentEvents;

  const InsightReportViewModel({
    required this.range,
    required this.events,
    required this.phaseAverages,
    required this.phaseDistribution,
    required this.monthlyStressByPhase,
    required this.triggers,
    required this.triggerByCyclePhaseMatrix,
    required this.triggerRanking,
    required this.totalEvents,
    required this.averageStress,
    required this.mostCommonCycleDay,
    required this.peakStressPhase,
    required this.recentEvents,
  });

  bool get hasData => totalEvents > 0;
  bool get hasPhaseData => phaseDistribution.totalLogs > 0;
}

class TriggerPhaseDetailViewModel {
  final String trigger;
  final String phase;
  final InsightDateRange range;
  final List<StressEvent> events;
  final List<TriggerPhaseCell> crossPhaseComparison;
  final int totalEvents;
  final double averageStress;
  final int? mostCommonCycleDay;

  const TriggerPhaseDetailViewModel({
    required this.trigger,
    required this.phase,
    required this.range,
    required this.events,
    required this.crossPhaseComparison,
    required this.totalEvents,
    required this.averageStress,
    required this.mostCommonCycleDay,
  });
}

class InsightAnalyticsService {
  static const phases = CyclePhaseUi.orderedPhases;

  InsightReportViewModel buildReport({
    required List<StressEvent> events,
    required List<Cycle> cycles,
    required InsightDateRange range,
  }) {
    final rangeEvents = _eventsInRange(events, range)
      ..sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
    final phaseDistribution = _phaseDistribution(rangeEvents, cycles);
    final phaseAverages = phases.map((phase) {
      final phaseEvents = rangeEvents
          .where((event) => phaseForEventOrNull(event, cycles) == phase)
          .toList();
      return PhaseAverage(
        phase: phase,
        count: phaseEvents.length,
        averageStress: _average(phaseEvents.map((event) => event.stressScore)),
      );
    }).toList();
    final peakStressPhase = phaseAverages
        .where((phase) => phase.count > 0)
        .fold<PhaseAverage?>(null, (best, current) {
          if (best == null) return current;
          return current.averageStress > best.averageStress ? current : best;
        })
        ?.phase;
    final triggers = _triggerRanking(
      rangeEvents,
    ).map((item) => item.trigger).take(5).toList();

    return InsightReportViewModel(
      range: range,
      events: rangeEvents,
      phaseAverages: phaseAverages,
      phaseDistribution: phaseDistribution,
      monthlyStressByPhase: _monthlyStress(rangeEvents, cycles, range),
      triggers: triggers,
      triggerByCyclePhaseMatrix: _matrix(rangeEvents, cycles, triggers),
      triggerRanking: _triggerRanking(rangeEvents),
      totalEvents: rangeEvents.length,
      averageStress: _average(rangeEvents.map((event) => event.stressScore)),
      mostCommonCycleDay: _mostCommonCycleDay(rangeEvents, cycles),
      peakStressPhase: peakStressPhase,
      recentEvents: rangeEvents.take(6).toList(),
    );
  }

  TriggerPhaseDetailViewModel buildDetail({
    required List<StressEvent> events,
    required List<Cycle> cycles,
    required InsightDateRange range,
    required String trigger,
    required String phase,
  }) {
    final normalizedPhase = normalizePhase(phase);
    final rangeEvents = _eventsInRange(events, range);
    final filtered =
        rangeEvents
            .where(
              (event) =>
                  _triggerKey(event.trigger) == _triggerKey(trigger) &&
                  phaseForEventOrNull(event, cycles) == normalizedPhase,
            )
            .toList()
          ..sort((a, b) => b.detectedAt.compareTo(a.detectedAt));

    return TriggerPhaseDetailViewModel(
      trigger: trigger,
      phase: normalizedPhase,
      range: range,
      events: filtered,
      crossPhaseComparison: phases.map((itemPhase) {
        final phaseEvents = rangeEvents
            .where(
              (event) =>
                  _triggerKey(event.trigger) == _triggerKey(trigger) &&
                  phaseForEventOrNull(event, cycles) == itemPhase,
            )
            .toList();
        return TriggerPhaseCell(
          trigger: trigger,
          phase: itemPhase,
          count: phaseEvents.length,
          averageStress: _average(
            phaseEvents.map((event) => event.stressScore),
          ),
        );
      }).toList(),
      totalEvents: filtered.length,
      averageStress: _average(filtered.map((event) => event.stressScore)),
      mostCommonCycleDay: _mostCommonCycleDay(filtered, cycles),
    );
  }

  List<StressEvent> eventsForDay({
    required List<StressEvent> events,
    required DateTime day,
  }) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return events
        .where((event) => event.isLoggedWithScore)
        .where(
          (event) =>
              !event.detectedAt.isBefore(start) &&
              event.detectedAt.isBefore(end),
        )
        .toList()
      ..sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
  }

  String? phaseForDate(DateTime date, List<Cycle> cycles) {
    final cycle = _cycleForDate(date, cycles);
    if (cycle == null) return null;

    final start = DateTime(
      cycle.lastPeriodStart.year,
      cycle.lastPeriodStart.month,
      cycle.lastPeriodStart.day,
    );
    final eventDate = DateTime(date.year, date.month, date.day);
    final cycleLength = cycle.cycleLength <= 0 ? 28 : cycle.cycleLength;
    final periodLength = (cycle.periodLength <= 0 ? 5 : cycle.periodLength)
        .clamp(1, cycleLength)
        .toInt();
    final diff = eventDate.difference(start).inDays;
    final cycleDay = (diff % cycleLength) + 1;

    return _phaseForDay(cycleDay, periodLength);
  }

  String phaseForEvent(StressEvent event, List<Cycle> cycles) {
    return phaseForEventOrNull(event, cycles) ?? 'unknown';
  }

  String? phaseForEventOrNull(StressEvent event, List<Cycle> cycles) {
    final day = cycleDayForEvent(event, cycles);
    if (day != null) {
      final cycle = _cycleForDate(event.detectedAt, cycles);
      return _phaseForDay(day, cycle?.periodLength ?? 5);
    }

    return null;
  }

  int? cycleDayForEvent(StressEvent event, List<Cycle> cycles) {
    final cycle = _cycleForDate(event.detectedAt, cycles);
    if (cycle == null) return null;

    final start = DateTime(
      cycle.lastPeriodStart.year,
      cycle.lastPeriodStart.month,
      cycle.lastPeriodStart.day,
    );
    final eventDate = DateTime(
      event.detectedAt.year,
      event.detectedAt.month,
      event.detectedAt.day,
    );
    final safeCycleLength = cycle.cycleLength <= 0 ? 28 : cycle.cycleLength;
    final diff = eventDate.difference(start).inDays;
    return (diff % safeCycleLength) + 1;
  }

  Cycle? _cycleForDate(DateTime date, List<Cycle> cycles) {
    if (cycles.isEmpty) return null;

    final eventDate = DateTime(date.year, date.month, date.day);
    final sortedCycles = [...cycles]
      ..sort((a, b) => b.lastPeriodStart.compareTo(a.lastPeriodStart));

    for (final cycle in sortedCycles) {
      final start = DateTime(
        cycle.lastPeriodStart.year,
        cycle.lastPeriodStart.month,
        cycle.lastPeriodStart.day,
      );
      if (!eventDate.isBefore(start)) return cycle;
    }

    return null;
  }

  String _phaseForDay(int day, int periodLength) {
    if (day <= periodLength) return 'menstrual';
    if (day <= 13) return 'follicular';
    if (day <= 16) return 'ovulation';
    return 'luteal';
  }

  static String normalizePhase(String phase) {
    return CyclePhaseUi.normalize(phase);
  }

  static String phaseLabel(String phase) {
    return CyclePhaseUi.of(phase).label;
  }

  static String phaseShortLabel(String phase) {
    return CyclePhaseUi.of(phase).shortLabel;
  }

  List<StressEvent> _eventsInRange(
    List<StressEvent> events,
    InsightDateRange range,
  ) {
    return events
        .where((event) => event.isLoggedWithScore)
        .where((event) => range.contains(event.detectedAt))
        .toList();
  }

  PhaseDistribution _phaseDistribution(
    List<StressEvent> events,
    List<Cycle> cycles,
  ) {
    final counts = {for (final phase in phases) phase: 0};
    for (final event in events) {
      final phase = phaseForEventOrNull(event, cycles);
      if (phase == null) continue;
      counts[phase] = (counts[phase] ?? 0) + 1;
    }

    final total = counts.values.fold<int>(0, (sum, count) => sum + count);
    return PhaseDistribution(
      totalLogs: total,
      items: [
        for (final phase in phases)
          PhaseDistributionItem(
            phase: phase,
            phaseLogCount: counts[phase] ?? 0,
            phaseDistributionRatio: total == 0
                ? 0
                : ((counts[phase] ?? 0) / total) * 100,
          ),
      ],
    );
  }

  List<MonthlyStressByPhase> _monthlyStress(
    List<StressEvent> events,
    List<Cycle> cycles,
    InsightDateRange range,
  ) {
    return List.generate(range.monthCount, (index) {
      final month = DateTime(range.start.year, range.start.month + index);
      final nextMonth = DateTime(month.year, month.month + 1);
      final monthEvents = events
          .where(
            (event) =>
                !event.detectedAt.isBefore(month) &&
                event.detectedAt.isBefore(nextMonth),
          )
          .toList();

      return MonthlyStressByPhase(
        month: month,
        averageByPhase: {
          for (final phase in phases)
            phase: _average(
              monthEvents
                  .where((event) => phaseForEventOrNull(event, cycles) == phase)
                  .map((event) => event.stressScore),
            ),
        },
        countByPhase: {
          for (final phase in phases)
            phase: monthEvents
                .where((event) => phaseForEventOrNull(event, cycles) == phase)
                .length,
        },
      );
    });
  }

  List<TriggerPhaseCell> _matrix(
    List<StressEvent> events,
    List<Cycle> cycles,
    List<String> triggers,
  ) {
    return [
      for (final trigger in triggers)
        for (final phase in phases)
          TriggerPhaseCell(
            trigger: trigger,
            phase: phase,
            count: events
                .where(
                  (event) =>
                      _triggerKey(event.trigger) == trigger &&
                      phaseForEventOrNull(event, cycles) == phase,
                )
                .length,
            averageStress: _average(
              events
                  .where(
                    (event) =>
                        _triggerKey(event.trigger) == trigger &&
                        phaseForEventOrNull(event, cycles) == phase,
                  )
                  .map((event) => event.stressScore),
            ),
          ),
    ];
  }

  List<TriggerRankingItem> _triggerRanking(List<StressEvent> events) {
    final triggers = events
        .map((event) => _triggerKey(event.trigger))
        .toSet()
        .toList();
    final ranking = triggers.map((trigger) {
      final triggerEvents = events
          .where((event) => _triggerKey(event.trigger) == trigger)
          .toList();
      return TriggerRankingItem(
        trigger: trigger,
        count: triggerEvents.length,
        averageStress: _average(
          triggerEvents.map((event) => event.stressScore),
        ),
      );
    }).toList();

    ranking.sort((a, b) {
      final countCompare = b.count.compareTo(a.count);
      if (countCompare != 0) return countCompare;
      return b.averageStress.compareTo(a.averageStress);
    });
    return ranking;
  }

  String _triggerKey(String value) {
    final trimmed = value.trim();
    final normalized = trimmed.toLowerCase();
    return switch (normalized) {
      '' || 'unknown' || 'uncategorized' => '',
      'work' => 'work',
      'social' => 'social',
      'family' => 'family',
      'school' => 'school',
      'health' => 'health',
      'other' => 'other',
      _ => trimmed,
    };
  }

  int? _mostCommonCycleDay(List<StressEvent> events, List<Cycle> cycles) {
    final counts = <int, int>{};
    for (final event in events) {
      final day = cycleDayForEvent(event, cycles);
      if (day == null) continue;
      counts[day] = (counts[day] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;

    return counts.entries.reduce((best, current) {
      if (current.value > best.value) return current;
      if (current.value == best.value && current.key < best.key) {
        return current;
      }
      return best;
    }).key;
  }

  double _average(Iterable<int?> values) {
    final list = values.whereType<int>().toList();
    if (list.isEmpty) return 0;
    return list.reduce((a, b) => a + b) / list.length;
  }
}
