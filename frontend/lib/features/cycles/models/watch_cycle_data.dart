class WatchCycleData {
  final DateTime periodStart;
  final DateTime? periodEnd;
  final int? estimatedCycleLength;
  final String source;

  const WatchCycleData({
    required this.periodStart,
    this.periodEnd,
    this.estimatedCycleLength,
    this.source = 'Galaxy Watch / Samsung Health',
  });
}
