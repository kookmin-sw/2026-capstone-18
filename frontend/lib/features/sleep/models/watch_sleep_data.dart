class WatchSleepData {
  final DateTime fellAsleepAt;
  final DateTime wokeUpAt;
  final DateTime endedOn;
  final String source;

  const WatchSleepData({
    required this.fellAsleepAt,
    required this.wokeUpAt,
    required this.endedOn,
    this.source = 'Galaxy Watch',
  });
}
