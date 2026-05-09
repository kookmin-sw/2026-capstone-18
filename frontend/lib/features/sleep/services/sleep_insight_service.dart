import '../models/sleep_log.dart';

class SleepInsightService {
  const SleepInsightService();

  String buildInsight({
    required SleepLog? latestLog,
    required List<SleepLog> history,
  }) {
    final records = _uniqueRecords(latestLog: latestLog, history: history);
    if (latestLog == null || records.length < 3) {
      return '수면 데이터가 조금 더 쌓이면 패턴을 알려드릴게요.';
    }

    final baseline = records
        .where((record) => record.id != latestLog.id)
        .toList();
    final comparisonRecords = baseline.length >= 2 ? baseline : records;
    final averageHours =
        comparisonRecords.fold<double>(
          0,
          (sum, record) => sum + record.durationHours,
        ) /
        comparisonRecords.length;

    final diffMinutes = ((latestLog.durationHours - averageHours) * 60).round();

    if (diffMinutes <= -30) {
      return '최근 수면 시간이 평균보다 ${diffMinutes.abs()}분 짧아요.';
    }
    if (diffMinutes >= 30) {
      return '최근 수면 시간이 평균보다 $diffMinutes분 길어요.';
    }
    return '최근 수면 패턴이 비교적 안정적이에요.';
  }

  List<SleepLog> _uniqueRecords({
    required SleepLog? latestLog,
    required List<SleepLog> history,
  }) {
    final recordsById = <String, SleepLog>{};
    for (final record in history) {
      recordsById[record.id] = record;
    }
    if (latestLog != null) {
      recordsById[latestLog.id] = latestLog;
    }

    return recordsById.values.toList()
      ..sort((a, b) => b.endedOn.compareTo(a.endedOn));
  }
}
