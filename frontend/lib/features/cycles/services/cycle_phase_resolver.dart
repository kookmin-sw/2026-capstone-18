class ResolvedCyclePhase {
  final int day;
  final String phase;

  const ResolvedCyclePhase({required this.day, required this.phase});
}

class CyclePhaseResolver {
  const CyclePhaseResolver._();

  static ResolvedCyclePhase resolve({
    required DateTime periodStart,
    required DateTime targetDate,
    required int cycleLength,
    required int periodLength,
  }) {
    final safeCycleLength = cycleLength <= 0 ? 28 : cycleLength;
    final safePeriodLength = periodLength <= 0 ? 7 : periodLength;
    final start = DateTime(
      periodStart.year,
      periodStart.month,
      periodStart.day,
    );
    final target = DateTime(targetDate.year, targetDate.month, targetDate.day);
    final diff = target.difference(start).inDays;
    final day = (diff % safeCycleLength) + 1;

    return ResolvedCyclePhase(
      day: day,
      phase: _phaseForDay(day: day, periodLength: safePeriodLength),
    );
  }

  static String _phaseForDay({required int day, required int periodLength}) {
    if (day <= periodLength) return 'menstrual';
    if (day <= 13) return 'follicular';
    if (day <= 16) return 'ovulation';
    return 'luteal';
  }
}
