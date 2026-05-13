import '../../cycles/models/cycle.dart';
import '../../cycles/services/cycle_phase_resolver.dart';

class InsightCalendarPhaseResolver {
  const InsightCalendarPhaseResolver._();

  static String? phaseForDate({
    required DateTime date,
    required List<Cycle> cycles,
    DateTime? today,
  }) {
    if (cycles.isEmpty) {
      return _defaultPhaseForMonthDay(date.day);
    }

    final cycle = _cycleForDate(date, cycles);
    if (cycle == null) return null;

    final dateOnly = _dateOnly(date);
    final start = _dateOnly(cycle.lastPeriodStart);
    final currentDay = _dateOnly(today ?? DateTime.now());

    if (cycle.periodOngoing &&
        cycle.periodEndDate == null &&
        !dateOnly.isBefore(start) &&
        !dateOnly.isAfter(currentDay)) {
      return 'menstrual';
    }

    final periodEnd = cycle.periodEndDate == null
        ? null
        : _dateOnly(cycle.periodEndDate!);
    if (periodEnd != null &&
        !dateOnly.isBefore(start) &&
        !dateOnly.isAfter(periodEnd)) {
      return 'menstrual';
    }

    return CyclePhaseResolver.resolve(
      periodStart: cycle.lastPeriodStart,
      targetDate: date,
      cycleLength: cycle.cycleLength,
      periodLength: cycle.periodLength,
    ).phase;
  }

  static String _defaultPhaseForMonthDay(int day) {
    if (day <= 5) return 'menstrual';
    if (day <= 13) return 'follicular';
    if (day <= 16) return 'ovulation';
    return 'luteal';
  }

  static Cycle? _cycleForDate(DateTime date, List<Cycle> cycles) {
    final dateOnly = _dateOnly(date);
    final sortedCycles = [...cycles]
      ..sort((a, b) => b.lastPeriodStart.compareTo(a.lastPeriodStart));

    for (final cycle in sortedCycles) {
      final start = _dateOnly(cycle.lastPeriodStart);
      if (!dateOnly.isBefore(start)) return cycle;
    }

    return null;
  }

  static DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }
}
