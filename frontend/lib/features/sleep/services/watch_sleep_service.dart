import 'package:flutter/services.dart';
import '../models/watch_sleep_data.dart';

class WatchSleepService {
  const WatchSleepService();

  static const _channel = MethodChannel('littlesignals/health');

  Future<WatchSleepData?> getLatestSleepData() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('getLatestSleepData');
    if (result == null) return null;
    return WatchSleepData(
      fellAsleepAt: DateTime.fromMillisecondsSinceEpoch(result['fell_asleep_at_ms'] as int),
      wokeUpAt: DateTime.fromMillisecondsSinceEpoch(result['woke_up_at_ms'] as int),
      endedOn: DateTime.fromMillisecondsSinceEpoch(result['ended_on_ms'] as int),
      source: result['source'] as String? ?? 'Galaxy Watch',
    );
  }
}
