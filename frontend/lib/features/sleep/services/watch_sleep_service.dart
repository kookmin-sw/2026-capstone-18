import 'package:flutter/services.dart';
import '../../health/health_connect_exception.dart';
import '../models/watch_sleep_data.dart';

class WatchSleepService {
  const WatchSleepService();

  static const _channel = MethodChannel('littlesignals/health');

  Future<WatchSleepData?> getLatestSleepData() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getLatestSleepData',
      );
      if (result == null) return null;
      return WatchSleepData(
        fellAsleepAt: DateTime.fromMillisecondsSinceEpoch(
          result['fell_asleep_at_ms'] as int,
        ),
        wokeUpAt: DateTime.fromMillisecondsSinceEpoch(
          result['woke_up_at_ms'] as int,
        ),
        endedOn: DateTime.fromMillisecondsSinceEpoch(
          result['ended_on_ms'] as int,
        ),
        source: result['source'] as String? ?? 'Galaxy Watch',
      );
    } on PlatformException catch (error) {
      throw HealthConnectException.fromPlatformException(error);
    }
  }

  Future<bool> requestPermission() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'requestHealthPermissions',
        {'kind': 'sleep'},
      );
      return result?['granted'] == true;
    } on PlatformException catch (error) {
      throw HealthConnectException.fromPlatformException(error);
    }
  }
}
