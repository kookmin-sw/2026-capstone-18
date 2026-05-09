import 'package:flutter/material.dart';

class AppColors {
  static const Color background = Color(0xFFFFFBFD);
  static const Color surface = Color(0xFFFFFFFF);

  static const Color textH = Color(0xFF201C28);
  static const Color textB = Color(0xFF483848);
  static const Color textM = Color(0xFF9888A0);
  static const Color textL = Color(0xFFC0B0C0);

  static const Color primary = Color(0xFFB87888);
  static const Color primaryPressed = Color(0xFFA76476);
  static const Color primaryLight = Color(0x94F3C4CE);

  static const Color triggerWork = Color(0xFFB87888);
  static const Color triggerSocial = Color(0xFFB7A6D8);
  static const Color triggerFamily = Color(0xFF94D0BC);
  static const Color triggerSchool = Color(0xFFAED3E8);
  static const Color triggerHealth = Color(0xFFE7C9A9);
  static const Color triggerOther = Color(0xFFD8D2D8);

  static const Color phaseMenstrual = Color(0xBFFFDAD5);
  static const Color phaseFollicular = Color(0xBFF2DCF3);
  static const Color phaseOvulation = Color(0xBFDDEDF8);
  static const Color phaseLuteal = Color(0xBF94D0BC);
}

Color triggerColorFor(String trigger) {
  return switch (trigger.trim().toLowerCase()) {
    'work' => AppColors.triggerWork,
    'social' => AppColors.triggerSocial,
    'family' => AppColors.triggerFamily,
    'school' => AppColors.triggerSchool,
    'health' => AppColors.triggerHealth,
    'other' => AppColors.triggerOther,
    _ => AppColors.triggerOther,
  };
}

class AppGradients {
  static const RadialGradient topGlow = RadialGradient(
    colors: [Color(0x99F2DCF3), Color(0x00E6B7E8)],
    stops: [0.0, 0.72],
  );

  static const RadialGradient bottomGlow = RadialGradient(
    colors: [Color(0x8AFFDAD5), Color(0x00FFBFB6)],
    stops: [0.0, 0.72],
  );

  static const RadialGradient sideGlow = RadialGradient(
    colors: [Color(0x52DDEDF8), Color(0x00DDEDF8)],
    stops: [0.0, 0.68],
  );
}
