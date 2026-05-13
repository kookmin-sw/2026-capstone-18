import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class CyclePhaseUi {
  final String phase;
  final String _fallbackLabel;

  const CyclePhaseUi._(this.phase, this._fallbackLabel);

  static const orderedPhases = [
    'menstrual',
    'follicular',
    'ovulation',
    'luteal',
  ];

  factory CyclePhaseUi.of(String phase) {
    return CyclePhaseUi._(normalize(phase), phase.trim());
  }

  static String normalize(String phase) {
    final normalized = phase.trim().toLowerCase();
    if (normalized.contains('menstrual') || normalized.contains('period')) {
      return 'menstrual';
    }
    if (normalized.contains('follicular')) return 'follicular';
    if (normalized.contains('ovulation') || normalized.contains('ovulatory')) {
      return 'ovulation';
    }
    if (normalized.contains('luteal')) return 'luteal';

    return switch (normalized) {
      'mens' => 'menstrual',
      'foll' => 'follicular',
      'ovul' => 'ovulation',
      'lut' => 'luteal',
      _ => normalized,
    };
  }

  String get label {
    return switch (phase) {
      'menstrual' => '생리기',
      'follicular' => '난포기',
      'ovulation' => '배란기',
      'luteal' => '황체기',
      'unknown' => '주기 정보 없음',
      _ => _fallbackLabel.isEmpty ? phase : _fallbackLabel,
    };
  }

  String get shortLabel {
    return switch (phase) {
      'menstrual' => '생리',
      'follicular' => '난포',
      'ovulation' => '배란',
      'luteal' => '황체',
      'unknown' => '정보 없음',
      _ => _fallbackLabel.isEmpty ? phase : _fallbackLabel,
    };
  }

  String get description {
    return switch (phase) {
      'menstrual' => '몸이 예민하게 느껴질 수 있어요. 휴식 신호를 조금 더 자주 확인해요.',
      'follicular' => '에너지가 서서히 올라오는 시기예요. 가벼운 루틴을 잡기 좋아요.',
      'ovulation' => '몸의 변화가 선명하게 느껴질 수 있어요. 스트레스 반응도 함께 살펴봐요.',
      'luteal' => '스트레스에 조금 더 민감해질 수 있어요. 무리하지 않아도 괜찮아요.',
      _ => '주기 흐름과 스트레스 기록을 함께 살펴볼게요.',
    };
  }

  Color get color {
    return switch (phase) {
      'menstrual' => AppColors.phaseMenstrual,
      'follicular' => AppColors.phaseFollicular,
      'ovulation' => AppColors.phaseOvulation,
      'luteal' => AppColors.phaseLuteal,
      _ => AppColors.triggerOther,
    };
  }

  Color get softBackgroundColor => color.withValues(alpha: 0.6);
}
