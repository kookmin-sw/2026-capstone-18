import '../services/cycle_phase_resolver.dart';

class Cycle {
  final String id;
  final DateTime lastPeriodStart;
  final DateTime? periodEndDate;
  final int cycleLength;
  final int periodLength;
  final String? notes;
  final String? backendPhase;
  final int? backendDay;

  const Cycle({
    required this.id,
    required this.lastPeriodStart,
    this.periodEndDate,
    required this.cycleLength,
    required this.periodLength,
    required this.notes,
    this.backendPhase,
    this.backendDay,
  });

  factory Cycle.fromJson(Map<String, dynamic> json) {
    final source = json['cycle'] is Map<String, dynamic>
        ? json['cycle'] as Map<String, dynamic>
        : json;
    final periodStart =
        source['period_start_date'] ?? source['last_period_start'];
    final lastPeriodStart = DateTime.tryParse('$periodStart') ?? DateTime.now();
    final periodEndRaw = source['period_end_date'] ?? source['period_end'];
    final periodEndDate = periodEndRaw == null
        ? null
        : DateTime.tryParse('$periodEndRaw');
    final derivedPeriodLength = periodEndDate == null
        ? null
        : periodEndDate.difference(lastPeriodStart).inDays + 1;

    return Cycle(
      id: '${source['id'] ?? source['cycle_id'] ?? ''}',
      lastPeriodStart: lastPeriodStart,
      periodEndDate: periodEndDate,
      cycleLength:
          (source['cycle_length_days'] as num?)?.round() ??
          (source['cycle_length'] as num?)?.round() ??
          28,
      periodLength:
          (source['period_length'] as num?)?.round() ??
          derivedPeriodLength ??
          7,
      notes: source['notes'] as String?,
      backendPhase: json['phase'] as String?,
      backendDay: (json['day'] as num?)?.round(),
    );
  }

  Map<String, dynamic> toCreateJson() {
    return {
      'period_start_date': _date(lastPeriodStart),
      'cycle_length_days': cycleLength,
      'auto_detected': false,
    };
  }

  Map<String, dynamic> toJson() {
    return {
      ...toCreateJson(),
      if (periodEndDate != null) 'period_end_date': _date(periodEndDate!),
    };
  }

  Map<String, dynamic> toPatchJson() {
    return {
      'period_start_date': _date(lastPeriodStart),
      if (periodEndDate != null) 'period_end_date': _date(periodEndDate!),
      'cycle_length_days': cycleLength,
    };
  }

  String get phase {
    return _resolvedPhase.phase;
  }

  int get cycleDay {
    return _resolvedPhase.day;
  }

  ResolvedCyclePhase get _resolvedPhase {
    return CyclePhaseResolver.resolve(
      periodStart: lastPeriodStart,
      targetDate: DateTime.now(),
      cycleLength: cycleLength,
      periodLength: periodLength,
    );
  }

  static String _date(DateTime date) {
    final dateOnly = DateTime(date.year, date.month, date.day);
    return dateOnly.toIso8601String().split('T').first;
  }
}
