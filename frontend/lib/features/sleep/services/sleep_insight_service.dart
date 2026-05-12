import '../models/sleep_log.dart';

class SleepInsightService {
  const SleepInsightService();

  String buildInsight({required List<SleepLog> records}) {
    final sortedRecords = _uniqueRecords(records);
    if (sortedRecords.isEmpty) {
      return '선택한 기간의 수면 기록이 아직 없어요.';
    }
    if (sortedRecords.length < 3) {
      return '기록이 더 쌓이면 선택한 기간의 수면 패턴을 보여드릴게요.';
    }

    final latestInRange = sortedRecords.first;
    final previousRecords = sortedRecords.skip(1).toList();
    final latestDurationHours = latestInRange.durationHours;
    final comparisonAverageHours =
        previousRecords.fold<double>(
          0,
          (sum, record) => sum + record.durationHours,
        ) /
        previousRecords.length;

    final diffMinutes = ((latestDurationHours - comparisonAverageHours) * 60)
        .round();

    if (diffMinutes <= -30) {
      return '선택 기간의 최근 수면 시간이 같은 기간 평균보다 ${diffMinutes.abs()}분 짧아요.';
    }
    if (diffMinutes >= 30) {
      return '선택 기간의 최근 수면 시간이 같은 기간 평균보다 $diffMinutes분 길어요.';
    }
    return '선택한 기간의 수면 패턴이 비교적 안정적이에요.';
  }

  List<SleepLog> _uniqueRecords(List<SleepLog> records) {
    final recordsById = <String, SleepLog>{};
    for (final record in records) {
      recordsById[record.id] = record;
    }

    return recordsById.values.toList()
      ..sort((a, b) => b.endedOn.compareTo(a.endedOn));
  }
}
