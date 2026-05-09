String koTrigger(String value) {
  final normalized = value.trim().toLowerCase();
  return switch (normalized) {
    'work' => '업무',
    'social' => '대인관계',
    'family' => '가족',
    'school' => '학업',
    'health' => '건강',
    'other' => '기타',
    'unknown' => '요인 불명',
    'uncategorized' => '요인 불명',
    '' => '요인 불명',
    _ => value,
  };
}

String koAccountType(String value) {
  return switch (value.toLowerCase()) {
    'anonymous' => '익명 계정',
    'google' => 'Google 계정',
    'email' => '이메일 계정',
    _ => value,
  };
}

String koNickname(String nickname) {
  final trimmed = nickname.trim();

  if (trimmed.isEmpty) {
    return '사용자님';
  }

  if (trimmed.endsWith('님')) {
    return trimmed;
  }

  return '$trimmed님';
}

String rawNickname(String nickname) {
  var trimmed = nickname.trim();
  while (trimmed.endsWith('님')) {
    trimmed = trimmed.substring(0, trimmed.length - 1).trimRight();
  }
  return trimmed;
}

String koPhase(String phase) {
  final normalized = phase.toLowerCase();
  if (normalized.contains('menstrual') || normalized.contains('period')) {
    return '생리기';
  }
  if (normalized.contains('follicular')) return '난포기';
  if (normalized.contains('ovulation')) return '배란기';
  if (normalized.contains('luteal')) return '황체기';
  return phase;
}

String koPhaseShort(String phase) {
  final normalized = phase.toLowerCase();
  if (normalized.contains('menstrual') || normalized.contains('period')) {
    return '생리';
  }
  if (normalized.contains('follicular')) return '난포';
  if (normalized.contains('ovulation')) return '배란';
  if (normalized.contains('luteal')) return '황체';
  return phase;
}

String koMonthLabel(DateTime date) {
  return '${date.year}년 ${date.month}월';
}

String koMonthDay(DateTime date) {
  return '${date.month}월 ${date.day}일';
}

String koFullDate(DateTime date) {
  return '${date.year}년 ${date.month}월 ${date.day}일';
}

String koYearMonthDay(DateTime date) {
  return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
}

String koTime(DateTime date) {
  final period = date.hour < 12 ? '오전' : '오후';
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  return '$period $hour:$minute';
}

String koMonthRange({
  required DateTime start,
  required DateTime endExclusive,
  required int monthCount,
}) {
  final endMonth = DateTime(endExclusive.year, endExclusive.month - 1);
  if (monthCount <= 1) return koMonthLabel(start);
  if (start.year == endMonth.year) {
    return '${start.year}년 ${start.month}월-${endMonth.month}월';
  }
  return '${koMonthLabel(start)}-${koMonthLabel(endMonth)}';
}

String koDays(int days) {
  return '$days일';
}
