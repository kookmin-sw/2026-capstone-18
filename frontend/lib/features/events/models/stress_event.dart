import 'package:flutter/foundation.dart';

enum StressEventState { detectedUnlogged, logged }

class StressEvent {
  final String id;
  final DateTime detectedAt;
  final bool stressDetected;
  final String cyclePhase;
  final int cycleDay;
  final bool logged;
  final List<String> logChips;
  final String? logText;
  final bool notified;
  final int? stressScore;
  final String? categoryId;
  final String trigger;
  final String? note;

  const StressEvent({
    required this.id,
    required this.detectedAt,
    this.stressDetected = true,
    this.cyclePhase = 'unknown',
    this.cycleDay = 0,
    this.logged = true,
    this.logChips = const [],
    this.logText,
    this.notified = false,
    this.stressScore,
    this.categoryId,
    required this.trigger,
    required this.note,
  });

  StressEventState get state =>
      logged ? StressEventState.logged : StressEventState.detectedUnlogged;

  bool get isLoggedWithScore => logged && stressScore != null;

  factory StressEvent.fromJson(Map<String, dynamic> json) {
    final chips =
        (json['log_chips'] as List?)?.whereType<String>().toList() ??
        const <String>[];
    final moodChips =
        (json['mood_chips'] as List?)?.whereType<String>().toList() ??
        const <String>[];
    final logged = json['logged'] == true;
    final rawScore =
        json['user_stress_level'] ??
        json['stress_score'] ??
        json['stressScore'];
    final stressDetected =
        json['stress_detected'] as bool? ?? json['stressDetected'] as bool?;

    return StressEvent(
      id: '${json['id'] ?? ''}',
      detectedAt: _detectedAtFromJson(json['detected_at']),
      stressDetected: stressDetected ?? true,
      cyclePhase: '${json['cycle_phase'] ?? 'unknown'}',
      cycleDay: (json['cycle_day'] as num?)?.round() ?? 0,
      logged: logged,
      logChips: chips,
      logText: json['log_text'] as String?,
      notified: json['notified'] == true,
      stressScore: logged && rawScore is num ? rawScore.round() : null,
      categoryId: json['category_id'] == null
          ? null
          : '${json['category_id']}'.trim(),
      trigger: chips.isNotEmpty
          ? chips.first
          : moodChips.isNotEmpty
          ? moodChips.first
          : (logged ? 'Unknown' : ''),
      note: json['log_text'] as String?,
    );
  }

  Map<String, dynamic> toCreateJson() {
    final chips = logChips.isEmpty
        ? (trigger.isEmpty ? <String>[] : [trigger])
        : logChips;
    final backendCyclePhase = _backendCyclePhase(cyclePhase);
    final backendCycleDay = _backendCycleDay(cycleDay);

    final body = <String, dynamic>{
      'detected_at': detectedAt.toUtc().toIso8601String(),
      'model_confidence': logged ? 1 : 0,
      if (stressScore != null) 'user_stress_level': stressScore,
      if (categoryId?.trim().isNotEmpty == true)
        'category_id': categoryId!.trim(),
      'mood_chips': const <String>[],
      'logged': logged,
      'log_chips': chips,
      if ((note ?? logText)?.isNotEmpty == true) 'log_text': note ?? logText,
      'notified': notified,
    };

    if (backendCyclePhase != null) {
      body['cycle_phase'] = backendCyclePhase;
    }
    if (backendCycleDay != null) {
      body['cycle_day'] = backendCycleDay;
    }

    return body;
  }

  StressEvent copyWith({
    String? id,
    DateTime? detectedAt,
    bool? stressDetected,
    String? cyclePhase,
    int? cycleDay,
    bool? logged,
    List<String>? logChips,
    String? logText,
    bool? notified,
    int? stressScore,
    String? categoryId,
    String? trigger,
    String? note,
  }) {
    return StressEvent(
      id: id ?? this.id,
      detectedAt: detectedAt?.toLocal() ?? this.detectedAt,
      stressDetected: stressDetected ?? this.stressDetected,
      cyclePhase: cyclePhase ?? this.cyclePhase,
      cycleDay: cycleDay ?? this.cycleDay,
      logged: logged ?? this.logged,
      logChips: logChips ?? this.logChips,
      logText: logText ?? this.logText,
      notified: notified ?? this.notified,
      stressScore: stressScore ?? this.stressScore,
      categoryId: categoryId ?? this.categoryId,
      trigger: trigger ?? this.trigger,
      note: note ?? this.note,
    );
  }

  static String? _backendCyclePhase(String value) {
    final normalized = value.trim().toLowerCase();
    return switch (normalized) {
      'menstrual' ||
      'period' ||
      'period phase' ||
      'menstrual phase' => 'menstrual',
      'follicular' || 'follicular phase' => 'follicular',
      'ovulation' || 'ovulatory' || 'ovulation phase' => 'ovulation',
      'luteal' || 'luteal phase' => 'luteal',
      _ => null,
    };
  }

  static int? _backendCycleDay(int value) {
    if (value < 1) return null;
    return value;
  }

  static DateTime _detectedAtFromJson(Object? value) {
    final raw = '${value ?? ''}';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return DateTime.now();

    final local = parsed.toLocal();
    assert(() {
      debugPrint('StressEvent.detectedAt raw=$raw');
      debugPrint('StressEvent.detectedAt isUtc=${parsed.isUtc}');
      debugPrint('StressEvent.detectedAt local=$local');
      return true;
    }());
    return local;
  }
}
