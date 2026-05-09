import 'package:flutter_test/flutter_test.dart';
import 'package:little_signals/features/sleep/models/sleep_log.dart';
import 'package:little_signals/features/sleep/services/sleep_insight_service.dart';

void main() {
  const service = SleepInsightService();

  test('returns fallback until enough sleep data is available', () {
    final latest = _sleepLog(
      id: 'sleep-1',
      fellAsleepAt: DateTime(2026, 5, 8, 23),
      wokeUpAt: DateTime(2026, 5, 9, 6),
    );

    expect(
      service.buildInsight(latestLog: latest, history: [latest]),
      '수면 데이터가 조금 더 쌓이면 패턴을 알려드릴게요.',
    );
  });

  test('compares latest sleep against recent average', () {
    final latest = _sleepLog(
      id: 'sleep-3',
      fellAsleepAt: DateTime(2026, 5, 8, 23),
      wokeUpAt: DateTime(2026, 5, 9, 6),
    );
    final history = [
      latest,
      _sleepLog(
        id: 'sleep-2',
        fellAsleepAt: DateTime(2026, 5, 7, 23),
        wokeUpAt: DateTime(2026, 5, 8, 7),
      ),
      _sleepLog(
        id: 'sleep-1',
        fellAsleepAt: DateTime(2026, 5, 6, 23),
        wokeUpAt: DateTime(2026, 5, 7, 7),
      ),
    ];

    expect(
      service.buildInsight(latestLog: latest, history: history),
      '최근 수면 시간이 평균보다 60분 짧아요.',
    );
  });
}

SleepLog _sleepLog({
  required String id,
  required DateTime fellAsleepAt,
  required DateTime wokeUpAt,
}) {
  return SleepLog(
    id: id,
    fellAsleepAt: fellAsleepAt,
    wokeUpAt: wokeUpAt,
    endedOn: DateTime(wokeUpAt.year, wokeUpAt.month, wokeUpAt.day),
  );
}
