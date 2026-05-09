class SleepLog {
  final String id;
  final DateTime fellAsleepAt;
  final DateTime wokeUpAt;
  final DateTime endedOn;

  const SleepLog({
    required this.id,
    required this.fellAsleepAt,
    required this.wokeUpAt,
    required this.endedOn,
  });

  factory SleepLog.fromJson(Map<String, dynamic> json) {
    final source = json['sleep_log'] is Map<String, dynamic>
        ? json['sleep_log'] as Map<String, dynamic>
        : json;

    return SleepLog(
      id: '${source['id'] ?? source['sleep_log_id'] ?? ''}',
      fellAsleepAt:
          DateTime.tryParse('${source['fell_asleep_at']}') ?? DateTime.now(),
      wokeUpAt: DateTime.tryParse('${source['woke_up_at']}') ?? DateTime.now(),
      endedOn: DateTime.tryParse('${source['ended_on']}') ?? DateTime.now(),
    );
  }

  double get durationHours {
    final minutes = wokeUpAt.difference(fellAsleepAt).inMinutes;
    if (minutes <= 0) return 0;
    return minutes / 60;
  }

  String get durationLabel {
    final totalMinutes = wokeUpAt
        .difference(fellAsleepAt)
        .inMinutes
        .clamp(0, 24 * 60);
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (minutes == 0) return '$hours시간';
    return '$hours시간 $minutes분';
  }

  Map<String, dynamic> toCreateJson() {
    return {
      'fell_asleep_at': fellAsleepAt.toUtc().toIso8601String(),
      'woke_up_at': wokeUpAt.toUtc().toIso8601String(),
      'ended_on': _date(endedOn),
    };
  }

  Map<String, dynamic> toUpdateJson() {
    return {
      'fell_asleep_at': fellAsleepAt.toUtc().toIso8601String(),
      'woke_up_at': wokeUpAt.toUtc().toIso8601String(),
    };
  }

  Map<String, dynamic> toJson() => toCreateJson();

  SleepLog copyWith({
    String? id,
    DateTime? fellAsleepAt,
    DateTime? wokeUpAt,
    DateTime? endedOn,
  }) {
    return SleepLog(
      id: id ?? this.id,
      fellAsleepAt: fellAsleepAt ?? this.fellAsleepAt,
      wokeUpAt: wokeUpAt ?? this.wokeUpAt,
      endedOn: endedOn ?? this.endedOn,
    );
  }

  static String _date(DateTime date) {
    final dateOnly = DateTime(date.year, date.month, date.day);
    return dateOnly.toIso8601String().split('T').first;
  }
}
